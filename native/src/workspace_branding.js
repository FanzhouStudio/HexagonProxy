(() => {
    if (window !== window.top || location.origin !== __WORKSPACE_ORIGIN__)
        return;

    const name = "HexagonLinux";
    const logo = "/__hexagonlinux/axolotl.svg";
    const logoSelector = "img.login-logo, .topbar .brand-button img.brand, img.about-logo";
    const removeUpstreamName = value => value.replace(/\bTuxee\b/g, name);

    function applyBrand() {
        // The marker identifies the actual Tuxee UI. Files and previews are left alone.
        if (!document.getElementById("tuxee-i18n"))
            return;
        if (!document.getElementById("hexagonlinux-style")) {
            const style = document.createElement("style");
            style.id = "hexagonlinux-style";
            style.textContent = `
                #app > .boot { background-image: url("${logo}") !important; }
                .hexagonlinux-login-name { margin: 0; text-align: center; font-size: clamp(20px, 5vw, 28px); }
                .about-content .hexagonlinux-credit { text-align: center; margin: 0; }
            `;
            document.head.append(style);
        }
        const title = removeUpstreamName(document.title);
        if (title !== document.title)
            document.title = title;
        for (const icon of document.querySelectorAll("link[rel='icon']")) {
            if (icon.getAttribute("href") !== logo) {
                icon.type = "image/svg+xml";
                icon.removeAttribute("sizes");
                icon.setAttribute("href", logo);
            }
        }
        for (const image of document.querySelectorAll(logoSelector)) {
            if (image.getAttribute("src") !== logo)
                image.setAttribute("src", logo);
            if (image.alt !== name)
                image.alt = name;
            if (image.classList.contains("login-logo") && !image.parentElement.querySelector(".hexagonlinux-login-name")) {
                const heading = document.createElement("h1");
                heading.className = "hexagonlinux-login-name";
                heading.textContent = name;
                image.after(heading);
            }
            if (image.classList.contains("about-logo") && !image.parentElement.querySelector(".hexagonlinux-credit")) {
                const credit = document.createElement("p");
                credit.className = "hexagonlinux-credit";
                credit.textContent = name + " · 基于 Tuxee";
                image.after(credit);
            }
        }
        for (const element of document.querySelectorAll(".topbar .brand-button, .about-modal [role='heading'], .about-modal h2")) {
            for (const attribute of ["title", "aria-label"]) {
                const before = element.getAttribute(attribute);
                if (before && removeUpstreamName(before) !== before)
                    element.setAttribute(attribute, removeUpstreamName(before));
            }
            if (!element.children.length && removeUpstreamName(element.textContent) !== element.textContent)
                element.textContent = removeUpstreamName(element.textContent);
        }
    }

    document.addEventListener("DOMContentLoaded", () => {
        applyBrand();
        const app = document.getElementById("app");
        if (!app || !document.getElementById("tuxee-i18n"))
            return;

        // Tuxee replaces the toolbar and its dialogs as login and theme change.
        const relevant = logoSelector + ", .about-modal";
        const observer = new MutationObserver(changes => {
            const changed = changes.some(change =>
                (change.type === "attributes" && change.target.matches(logoSelector)) ||
                Array.from(change.addedNodes).some(node =>
                    node.nodeType === Node.ELEMENT_NODE &&
                    (node.matches(relevant) || node.querySelector(relevant))));
            if (changed)
                applyBrand();
        });
        observer.observe(document.body, {childList: true, subtree: true, attributes: true, attributeFilter: ["src", "alt"]});
        const title = document.querySelector("title");
        if (title)
            new MutationObserver(applyBrand).observe(title, {childList: true, subtree: true, characterData: true});
    }, {once: true});
})();
