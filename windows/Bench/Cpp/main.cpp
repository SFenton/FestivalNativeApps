/// @file main.cpp
/// @brief C++/WinRT twin of Bench/CSharp: one WinUI 3 window, a label and a full-window image with a
///        stepped 6 s zoom on the composition thread. Used only to measure the language/runtime floor.
///        Arguments: --static (no animation), --perf-log <path> (writes activated/first-frame markers).

#include <windows.h>
#include <chrono>
#include <fstream>
#include <string>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.Numerics.h>
#include <winrt/Microsoft.UI.h>
#include <winrt/Microsoft.UI.Composition.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

using namespace winrt;
using namespace winrt::Microsoft::UI;
using namespace winrt::Microsoft::UI::Composition;
using namespace winrt::Microsoft::UI::Xaml;

namespace
{
    std::wstring g_log;
    bool g_static = false;

    /// @brief Milliseconds since the OS recorded process start.
    double SinceProcessStart()
    {
        FILETIME created{}, exited{}, kernel{}, user{};
        GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user);
        FILETIME now{};
        GetSystemTimePreciseAsFileTime(&now);
        auto ticks = [](FILETIME const& f) { return (static_cast<unsigned long long>(f.dwHighDateTime) << 32) | f.dwLowDateTime; };
        return (ticks(now) - ticks(created)) / 10000.0;
    }

    /// @brief Appends one name=ms marker to the perf log.
    void Mark(char const* name)
    {
        if (g_log.empty()) return;
        std::ofstream(g_log, std::ios::app) << name << '=' << SinceProcessStart() << '\n';
    }
}

/// @brief Benchmark application.
struct App : ApplicationT<App>
{
    Window m_window{ nullptr };
    Visual m_sprite{ nullptr };
    bool m_firstFrame = false;
    winrt::event_token m_rendering{};

    /// @brief Builds the window and starts the animation.
    void OnLaunched(LaunchActivatedEventArgs const&)
    {
        m_window = Window();
        Controls::Grid grid;
        grid.Background(Media::SolidColorBrush(Colors::Black()));
        Controls::TextBlock text;
        text.Text(L"Benchmark (C++/WinRT)");
        text.Margin(ThicknessHelper::FromUniformLength(24));
        grid.Children().Append(text);
        m_window.Content(grid);

        grid.Loaded([this, grid](auto&&, auto&&)
        {
            auto compositor = Hosting::ElementCompositionPreview::GetElementVisual(grid).Compositor();
            auto sprite = compositor.CreateSpriteVisual();
            sprite.Size({ 1400.0f, 900.0f });
            sprite.CenterPoint({ 700.0f, 450.0f, 0.0f });
            wchar_t path[MAX_PATH]{};
            GetModuleFileNameW(nullptr, path, MAX_PATH);
            std::wstring dir(path);
            dir = dir.substr(0, dir.find_last_of(L'\\'));
            auto surface = Media::LoadedImageSurface::StartLoadFromUri(Windows::Foundation::Uri(L"file:///" + dir + L"/bench-art.png"), { 1024, 1024 });
            auto brush = compositor.CreateSurfaceBrush(surface);
            brush.Stretch(CompositionStretch::UniformToFill);
            sprite.Brush(brush);
            Hosting::ElementCompositionPreview::SetElementChildVisual(grid, sprite);
            if (!g_static)
            {
                auto scale = compositor.CreateVector3KeyFrameAnimation();
                auto steps = compositor.CreateStepEasingFunction(180);
                steps.IsFinalStepSingleFrame(false);
                scale.InsertKeyFrame(0.0f, { 1.0f, 1.0f, 1.0f });
                scale.InsertKeyFrame(1.0f, { 1.18f, 1.18f, 1.0f }, steps);
                scale.Duration(std::chrono::seconds(6));
                scale.IterationBehavior(AnimationIterationBehavior::Forever);
                scale.Direction(AnimationDirection::Alternate);
                sprite.StartAnimation(L"Scale", scale);
            }
            m_sprite = sprite;
            // Unsubscribe after the first frame: a live Rendering handler makes XAML render every frame.
            m_rendering = Media::CompositionTarget::Rendering([this](auto&&, auto&&)
            {
                if (m_firstFrame) return;
                m_firstFrame = true;
                Mark("first-frame");
                Media::CompositionTarget::Rendering(m_rendering);
            });
        });
        m_window.Activated([](auto&&, auto&&) { Mark("window-activated"); });
        m_window.Activate();
    }
};

/// @brief Entry point.
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    int argc = 0;
    auto argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    for (int i = 1; i < argc; ++i)
    {
        std::wstring arg = argv[i];
        if (arg == L"--static") g_static = true;
        else if (arg == L"--perf-log" && i + 1 < argc) g_log = argv[++i];
    }
    LocalFree(argv);
    init_apartment(apartment_type::single_threaded);
    Application::Start([](auto&&) { make<App>(); });
    return 0;
}
