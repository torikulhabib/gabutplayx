# Gabut PlayX Player

A modern high-performance video player built with Vala and GTK4, designed to deliver smooth multimedia playback with native Linux hardware acceleration support.

## Features

- 🎬 Modern GTK4 user interface
- ⚡ Hardware accelerated video decoding
- 🔥 VA-API hardware acceleration integration
- 🎵 High quality audio playback
- 📂 Drag and drop media support
- ⏩ Fast seeking and smooth playback
- 🌙 Clean and lightweight design
- 🐧 Native Linux desktop integration
- 🚀 Optimized low CPU usage for high-resolution videos
- 🧩 Does not require `gtk4paintablesink` Rust-based libraries
- 🔧 Pure native integration without external Rust GTK video sink dependencies

## Hardware Acceleration

The player integrates multiple hardware acceleration backends to maximize performance and reduce CPU load during video playback.

### Supported Accelerators

#### VA-API
Video Acceleration API support for Intel and AMD GPUs.

Features:
- Hardware video decoding
- Reduced CPU utilization
- Efficient power consumption
- Smooth 4K playback
- Optimized rendering pipeline
- Smooth high bitrate playback
- Efficient GPU video processing

## Native Rendering Pipeline

Unlike many GTK4 multimedia applications, PlayX does not depend on:

- `gtk4paintablesink`
- Rust-based GTK video sink libraries
- External GTK rendering wrappers

Instead, the application uses a lightweight native rendering pipeline optimized directly for Vala, GTK4, Dmabuf hardware accelerated video output.

Benefits:
- Faster startup time
- Reduced dependency size
- Easier distribution
- Lower memory overhead
- Better compatibility across Linux distributions
- Cleaner native integration

## Built With

- **Vala (Valac)**
- **GTK4**
- **GStreamer**

## Performance Goals

This project focuses on:
- Minimal memory usage
- Maximum playback smoothness
- Native Linux performance
- Efficient GPU utilization
- Modern responsive UI

## Why Vala?

Vala provides:
- Native compiled performance
- Simple and clean syntax
- Excellent GTK integration
- Low-level Linux system access
- Fast application startup

## Screenshot

<img src="https://raw.githubusercontent.com/gabutakut/gabutplayx/master/Screenshot0.png" alt="Home">

## Requirements

### Runtime Dependencies

- GTK4
- GStreamer
- VA-API drivers
- Dmabuf
- MemoryTexture

### Build Dependencies

```bash
sudo apt install valac gtk4 libgtk-4-dev \
gstreamer1.0-* libgstreamer1.0-dev
