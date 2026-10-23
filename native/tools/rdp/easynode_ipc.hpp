// EasyNode additions to the Apache-2.0 FreeRDP SDL3 frontend.
// The official frontend retains rendering, input, clipboard and certificate UI.
#pragma once
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <thread>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

namespace easynode {
inline bool read_password(rdpSettings* settings)
{
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
#endif
    const char* config = std::getenv("EASYNODE_RDP_CONFIG");
    if (!config || !freerdp_settings_set_string(settings, FreeRDP_ConfigPath, config)) return false;
    unsigned char header[4] = {};
    if (std::fread(header, 1, 4, stdin) != 4) return false;
    const uint32_t size = (uint32_t(header[0]) << 24) | (uint32_t(header[1]) << 16) |
                          (uint32_t(header[2]) << 8) | uint32_t(header[3]);
    if (size > 65536) return false;
    std::vector<char> password(size + 1, '\0');
    if (std::fread(password.data(), 1, size, stdin) != size) return false;
    const bool result = freerdp_settings_set_string(settings, FreeRDP_Password, password.data());
    // Volatile writes prevent optimization of the temporary password wipe.
    volatile char* bytes = password.data();
    for (size_t i = 0; i < password.size(); ++i) bytes[i] = 0;
    return result;
}
inline void focus(void*)
{
    int count = 0;
    SDL_Window** windows = SDL_GetWindows(&count);
    for (int i = 0; i < count; ++i) {
        if (SDL_GetWindowFlags(windows[i]) & SDL_WINDOW_MINIMIZED)
            SDL_RestoreWindow(windows[i]);
        SDL_RaiseWindow(windows[i]);
    }
    SDL_free(windows);
}
inline void control(rdpContext* context)
{
    // One helper per window. A detached pipe reader must never keep the process
    // alive after the SDL main loop exits; EOF also prevents orphan windows.
    std::thread([context]() {
        char buffer[32];
        while (std::fgets(buffer, sizeof(buffer), stdin)) {
            const std::string command(buffer);
            if (command == "focus\n") {
                SDL_RunOnMainThread(focus, nullptr, false);
            } else if (command == "close\n") {
                freerdp_abort_connect_context(context);
                SDL_Event event = {};
                event.type = SDL_EVENT_QUIT;
                SDL_PushEvent(&event);
                return;
            }
        }
        std::_Exit(0);
    }).detach();
}
inline void connected()
{
    std::puts("EASYNODE_RDP connected");
    std::fflush(stdout);
}
} // namespace easynode
