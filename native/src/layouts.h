#pragma once
#include <QtWidgets>
namespace hexagon {
// Action rows wrap only on a resize or font change; controls retain identity.
class ActionLayout : public QHBoxLayout {
  public:
    using QHBoxLayout::QHBoxLayout;
    bool hasHeightForWidth() const override {
        return true;
    }
    int heightForWidth(int width) const override {
        return arrange(QRect(0, 0, width, 0), false);
    }
    QSize minimumSize() const override {
        QSize result;
        for (int i = 0; i < count(); ++i)
            if (itemAt(i)->widget())
                result = result.expandedTo(itemAt(i)->minimumSize());
        return result;
    }
    QSize sizeHint() const override {
        return QSize(600, heightForWidth(600));
    }
    void setGeometry(const QRect &rect) override {
        QLayout::setGeometry(rect);
        arrange(rect, true);
    }

  private:
    int arrange(QRect rect, bool apply) const {
        int y = rect.y(), x = rect.x(), height = 0;
        const int gap = spacing() < 0 ? 8 : spacing();
        QList<int> row;
        QList<int> widths;
        int used = 0;
        auto finish = [&] {
            int weight = 0;
            for (int i : row)
                weight += stretch(i);
            int extra = qMax(0, rect.width() - used);
            int left = rect.x();
            for (int k = 0; k < row.size(); ++k) {
                int i = row[k];
                int width = widths[k] + (weight ? extra * stretch(i) / weight : 0);
                if (apply)
                    itemAt(i)->setGeometry(QRect(left, y, width, height));
                left += width + gap;
            }
            y += height + gap;
            row.clear();
            widths.clear();
            used = 0;
            height = 0;
            x = rect.x();
        };
        for (int i = 0; i < count(); ++i) {
            auto item = itemAt(i);
            if (!item->widget() || item->isEmpty())
                continue;
            int width =
                qMin(rect.width(), qMax(item->minimumSize().width(),
                                        qMin(item->sizeHint().width(), stretch(i) > 0 ? 320 : rect.width())));
            if (!row.empty() && used + gap + width > rect.width())
                finish();
            if (!row.empty())
                used += gap;
            row << i;
            widths << width;
            used += width;
            height = qMax(height, item->sizeHint().height());
        }
        if (!row.empty())
            finish();
        Q_UNUSED(x);
        return qMax(0, y - rect.y() - gap);
    }
};
class PagedTree : public QTreeWidget {
  public:
    explicit PagedTree(QWidget *parent = nullptr) : QTreeWidget(parent) {
        setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    }
    QLabel *counter = nullptr;
    QPushButton *previous = nullptr, *next = nullptr;
    int page = 0, perPage = 1;
    void paginate() {
        if (!counter)
            return;
        int rowHeight = fontMetrics().height() + 16;
        if (topLevelItemCount())
            rowHeight = qMax(rowHeight, sizeHintForRow(0));
        perPage = qMax(1, viewport()->height() / qMax(1, rowHeight));
        int total = qMax(1, (topLevelItemCount() + perPage - 1) / perPage);
        page = qBound(0, page, total - 1);
        for (int i = 0; i < topLevelItemCount(); ++i)
            topLevelItem(i)->setHidden(i / perPage != page);
        if (currentItem() && currentItem()->isHidden() && topLevelItemCount())
            setCurrentItem(topLevelItem(page * perPage));
        counter->setText(QString("第 %1 / %2 页 · %3 条").arg(page + 1).arg(total).arg(topLevelItemCount()));
        previous->setEnabled(page > 0);
        next->setEnabled(page + 1 < total);
    }

  protected:
    void resizeEvent(QResizeEvent *event) override {
        QTreeWidget::resizeEvent(event);
        QTimer::singleShot(0, this, [this] { paginate(); });
    }
};
inline QVBoxLayout *tabPage(QTabWidget *tabs, const QString &name) {
    auto widget = new QWidget;
    auto layout = new QVBoxLayout(widget);
    layout->setContentsMargins(0, 12, 0, 0);
    layout->setSpacing(12);
    tabs->addTab(widget, name);
    return layout;
}

class AdaptivePanels : public QWidget {
  public:
    AdaptivePanels(int wideMin, int columns, int wideHeight = 0)
        : wideMin(wideMin), columns(columns), wideHeight(wideHeight) {
        auto layout = new QVBoxLayout(this);
        layout->setContentsMargins(0, 0, 0, 0);
        tabs = new QTabBar;
        tabs->setExpanding(false);
        layout->addWidget(tabs);
        auto body = new QWidget;
        grid = new QGridLayout(body);
        grid->setContentsMargins(0, 0, 0, 0);
        grid->setSpacing(12);
        layout->addWidget(body, 1);
        connect(tabs, &QTabBar::currentChanged, this, [this] { arrange(); });
    }
    QVBoxLayout *addPanel(const QString &title) {
        auto widget = new QWidget(grid->parentWidget());
        auto layout = new QVBoxLayout(widget);
        layout->setContentsMargins(0, 0, 0, 0);
        layout->setSpacing(10);
        panels.append(widget);
        tabs->addTab(title);
        arrange();
        return layout;
    }
    void showPanel(int index) {
        tabs->setCurrentIndex(index);
        arrange();
    }
    void setRowStretch(int row, int stretch) {
        rowWeights[row] = stretch;
        arrange();
    }
    void setColumnStretch(int column, int stretch) {
        weights[column] = stretch;
        arrange();
    }
    void arrange() {
        if (arranging)
            return;
        const QScopedValueRollback guard(arranging, true);
        const int fontExtra = qMax(0, fontMetrics().height() - 24);
        const bool wide =
            width() >= wideMin + fontExtra * 9 && (!wideHeight || height() >= wideHeight + fontExtra * 8);
        tabs->setVisible(!wide);
        for (int i = 0; i < columns; ++i)
            grid->setColumnStretch(i, wide ? weights.value(i, 1) : (i == 0 ? 1 : 0));
        for (auto it = rowWeights.cbegin(); it != rowWeights.cend(); ++it)
            grid->setRowStretch(it.key(), wide ? it.value() : 0);
        for (int i = 0; i < panels.size(); ++i) {
            auto widget = panels.at(i);
            grid->removeWidget(widget);
            if (wide || i == tabs->currentIndex()) {
                grid->addWidget(widget, wide ? i / columns : 0, wide ? i % columns : 0);
                widget->show();
            } else {
                widget->hide();
            }
        }
    }

  protected:
    void resizeEvent(QResizeEvent *event) override {
        QWidget::resizeEvent(event);
        arrange();
    }

  private:
    int wideMin, columns, wideHeight;
    QTabBar *tabs;
    QGridLayout *grid;
    QList<QWidget *> panels;
    QHash<int, int> weights, rowWeights;
    bool arranging = false;
};

class CardPager : public QWidget {
  public:
    explicit CardPager(int preferredCardWidth = 0, int maximumColumns = 1)
        : preferredCardWidth(preferredCardWidth), maximumColumns(maximumColumns) {
        auto layout = new QVBoxLayout(this);
        layout->setContentsMargins(0, 0, 0, 0);
        layout->setSpacing(8);
        body = new QWidget;
        layout->addWidget(body, 1);
        grid = new QGridLayout(body);
        grid->setContentsMargins(0, 0, 0, 0);
        grid->setSpacing(8);
        empty = new QLabel;
        empty->setWordWrap(true);
        grid->addWidget(empty, 0, 0);
        footer = new QWidget;
        auto actions = new QHBoxLayout(footer);
        actions->setContentsMargins(0, 0, 0, 0);
        previous = new QPushButton("上一页");
        next = new QPushButton("下一页");
        counter = new QLabel;
        actions->addWidget(previous);
        actions->addWidget(counter, 1, Qt::AlignCenter);
        actions->addWidget(next);
        layout->addWidget(footer);
        connect(previous, &QPushButton::clicked, this, [this] {
            --page;
            arrange();
        });
        connect(next, &QPushButton::clicked, this, [this] {
            ++page;
            arrange();
        });
    }
    void setCards(QList<QWidget *> items, const QString &emptyMessage) {
        for (auto widget : cards) {
            grid->removeWidget(widget);
            widget->hide();
            widget->deleteLater();
        }
        cards = std::move(items);
        for (auto widget : cards) {
            widget->setParent(body);
            widget->hide();
        }
        empty->setText(emptyMessage);
        arrange();
    }
    void arrange() {
        const int width = qMax(1, body->width());
        const int columns = preferredCardWidth ? qBound(1, width / preferredCardWidth, maximumColumns) : 1;
        int rowHeight = fontMetrics().height() * 2 + 40;
        const int cardWidth = width / columns - 8;
        for (auto widget : cards) {
            const int height = widget->heightForWidth(cardWidth);
            rowHeight = qMax(rowHeight, qMax(widget->sizeHint().height(), height));
        }
        const int available = height() - footer->sizeHint().height() - 8;
        const int perPage = qMax(1, (available + 8) / (rowHeight + 8)) * columns;
        const int pages = qMax(1, (int(cards.size()) + perPage - 1) / perPage);
        page = qBound(0, page, pages - 1);
        for (int column = 0; column < maximumColumns; ++column)
            grid->setColumnStretch(column, column < columns ? 1 : 0);
        for (int i = 0; i < cards.size(); ++i) {
            auto widget = cards.at(i);
            const int offset = i - page * perPage;
            grid->removeWidget(widget);
            if (offset >= 0 && offset < perPage) {
                grid->addWidget(widget, offset / columns, offset % columns, Qt::AlignTop);
                widget->show();
            } else {
                widget->hide();
            }
        }
        grid->setAlignment(Qt::AlignTop);
        empty->setVisible(cards.isEmpty());
        footer->setVisible(pages > 1);
        previous->setEnabled(page > 0);
        next->setEnabled(page + 1 < pages);
        counter->setText(QString("%1 / %2 页 · %3 项").arg(page + 1).arg(pages).arg(cards.size()));
    }

  protected:
    void resizeEvent(QResizeEvent *event) override {
        QWidget::resizeEvent(event);
        QTimer::singleShot(0, this, [this] { arrange(); });
    }

  private:
    int preferredCardWidth, maximumColumns, page = 0;
    QWidget *body, *footer;
    QGridLayout *grid;
    QLabel *empty, *counter;
    QPushButton *previous, *next;
    QList<QWidget *> cards;
};

} // namespace hexagon
