#include <windows.h>
#include <bcrypt.h>
#include <filesystem>
#include <fstream>
#include <shellapi.h>
#include <shlobj.h>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;
static std::wstring quote(const std::wstring &value) {
    std::wstring out = L"\"";
    int slash = 0;
    for (wchar_t ch : value) {
        if (ch == L'\\') {
            ++slash;
            continue;
        }
        if (ch == L'"') {
            out.append(2 * slash + 1, L'\\');
            out += ch;
        } else {
            out.append(slash, L'\\');
            out += ch;
        }
        slash = 0;
    }
    out.append(2 * slash, L'\\');
    out += L'"';
    return out;
}
static std::wstring errorMessage(DWORD code) {
    LPWSTR message = nullptr;
    FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                       FORMAT_MESSAGE_IGNORE_INSERTS,
                   nullptr, code, 0, reinterpret_cast<LPWSTR>(&message), 0, nullptr);
    std::wstring text = message ? message : L"Windows operation failed";
    if (message)
        LocalFree(message);
    return text;
}
static DWORD run(const fs::path &program, const std::vector<std::wstring> &args, const fs::path &working) {
    std::wstring command = quote(program.wstring());
    for (const auto &a : args)
        command += L" " + quote(a);
    STARTUPINFOW si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    if (!CreateProcessW(program.c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr,
                        working.c_str(), &si, &pi))
        throw std::runtime_error("Cannot start embedded application");
    CloseHandle(pi.hThread);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    return code;
}
static std::string sha256(const BYTE *data, DWORD size) {
    BCRYPT_ALG_HANDLE algorithm{};
    BCRYPT_HASH_HANDLE hash{};
    DWORD length = 0, written = 0;
    std::vector<BYTE> state, digest(32);
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0)
        throw std::runtime_error("SHA256 initialization failed");
    BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&length), sizeof(length),
                      &written, 0);
    state.resize(length);
    if (BCryptCreateHash(algorithm, &hash, state.data(), length, nullptr, 0, 0) < 0 ||
        BCryptHashData(hash, const_cast<PUCHAR>(data), size, 0) < 0 ||
        BCryptFinishHash(hash, digest.data(), 32, 0) < 0)
        throw std::runtime_error("Payload checksum failed");
    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(algorithm, 0);
    std::string text;
    const char *hex = "0123456789abcdef";
    for (auto b : digest) {
        text += hex[b >> 4];
        text += hex[b & 15];
    }
    return text;
}
static std::wstring utf16(const std::string &input) {
    int size =
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), int(input.size()), nullptr, 0);
    if (size <= 0)
        return {};
    std::wstring out(size, L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), int(input.size()), out.data(), size);
    return out;
}
static bool complete(const fs::path &dir) {
    if (!fs::exists(dir / L".ready") || !fs::exists(dir / L"HexagonProxy.exe"))
        return false;
    std::ifstream list(dir / L"files.list");
    if (!list)
        return false;
    std::string line;
    while (std::getline(list, line)) {
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        auto relative = fs::path(utf16(line));
        if (relative.is_absolute() || line.find("..") != std::string::npos ||
            !fs::is_regular_file(dir / relative))
            return false;
    }
    return true;
}
int WINAPI wWinMain(HINSTANCE module, HINSTANCE, LPWSTR, int) {
    try {
        auto resource = FindResourceW(module, MAKEINTRESOURCEW(101), RT_RCDATA);
        if (!resource)
            throw std::runtime_error("Embedded runtime was not found");
        auto handle = LoadResource(module, resource);
        auto data = static_cast<const BYTE *>(LockResource(handle));
        DWORD size = SizeofResource(module, resource);
        const auto digest = sha256(data, size);
        PWSTR local = nullptr;
        if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local)))
            throw std::runtime_error("Cannot locate current user application data");
        fs::path cache = fs::path(local) / L"FanzhouStudio" / L"HexagonProxy" / L"runtime";
        CoTaskMemFree(local);
        fs::create_directories(cache);
        fs::path destination = cache / fs::path(digest.substr(0, 20));
        std::wstring mutexName = L"Local\\HexagonProxy-runtime-" + utf16(digest.substr(0, 20));
        HANDLE mutex = CreateMutexW(nullptr, FALSE, mutexName.c_str());
        if (!mutex)
            throw std::runtime_error("Cannot lock runtime extraction");
        DWORD wait = WaitForSingleObject(mutex, 180000);
        if (wait != WAIT_OBJECT_0 && wait != WAIT_ABANDONED) {
            CloseHandle(mutex);
            throw std::runtime_error("Another runtime extraction has not finished");
        }
        if (!complete(destination)) {
            const auto staging = cache / (L".extract-" + std::to_wstring(GetCurrentProcessId()));
            // Only this invocation's direct child of our private cache can be removed.
            if (staging.parent_path() != cache || staging.filename().wstring().rfind(L".extract-", 0) != 0)
                throw std::runtime_error("Unsafe staging directory");
            fs::remove_all(staging);
            fs::create_directories(staging);
            auto zip = staging / L"payload.zip";
            {
                std::ofstream f(zip, std::ios::binary);
                f.write(reinterpret_cast<const char *>(data), size);
                if (!f)
                    throw std::runtime_error("Cannot write embedded runtime");
            }
            wchar_t system[MAX_PATH]{};
            GetSystemDirectoryW(system, MAX_PATH);
            DWORD code = run(fs::path(system) / L"tar.exe", {L"-xf", zip.wstring(), L"-C", staging.wstring()},
                             staging);
            if (code)
                throw std::runtime_error("Cannot extract embedded runtime");
            fs::remove(zip);
            {
                std::ofstream marker(staging / L".ready");
                marker << digest;
            }
            if (!complete(staging))
                throw std::runtime_error("Extracted runtime is incomplete");
            if (fs::exists(destination)) {
                if (destination.parent_path() != cache)
                    throw std::runtime_error("Unsafe runtime path");
                fs::remove_all(destination);
            }
            fs::rename(staging, destination);
        }
        ReleaseMutex(mutex);
        CloseHandle(mutex);
        int argc = 0;
        auto argv = CommandLineToArgvW(GetCommandLineW(), &argc);
        std::vector<std::wstring> arguments;
        bool extract = false;
        for (int i = 1; i < argc; ++i) {
            if (std::wstring(argv[i]) == L"--extract-only")
                extract = true;
            else
                arguments.emplace_back(argv[i]);
        }
        LocalFree(argv);
        if (extract) {
            auto text = destination.string() + "\r\n";
            DWORD written;
            WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), text.data(), DWORD(text.size()), &written, nullptr);
            return 0;
        }
        wchar_t own[32768]{};
        GetModuleFileNameW(nullptr, own, 32768);
        SetEnvironmentVariableW(L"HEXAGON_LAUNCHER", own);
        SetEnvironmentVariableW(L"HEXAGON_RESOURCE_DIR", (destination / L"resources").c_str());
        SetEnvironmentVariableW(L"QT_PLUGIN_PATH", destination.c_str());
        return int(run(destination / L"HexagonProxy.exe", arguments, destination));
    } catch (const std::exception &e) {
        auto text = L"HexagonProxy 启动失败：\n" + utf16(e.what()) + L"\n" + errorMessage(GetLastError());
        MessageBoxW(nullptr, text.c_str(), L"HexagonProxy", MB_OK | MB_ICONERROR);
        return 1;
    }
}
