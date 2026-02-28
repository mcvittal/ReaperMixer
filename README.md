# Reaper Live Mixer

A web-based remote control interface for Reaper DAW, designed for live sound mixing. Provides fader control, EQ, dynamics processing, and metering through a browser interface.

## Features

- 32-channel fader control with volume, pan, mute, and solo
- Per-channel EQ (Low, Lo-Mid, Hi-Mid, High + HPF)
- Per-channel dynamics (Gate + Compressor)
- VU metering
- Master bus EQ
- Touch-friendly interface for tablets
- Real-time OSC communication with Reaper

## Prerequisites

- **Reaper DAW** (v6.0+)
- **Node.js** (v16 or higher)
- **npm** (comes with Node.js)

## Installation on Linux

### 1. Install Node.js

```bash
# Ubuntu/Debian
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Fedora
sudo dnf install nodejs

# Arch Linux
sudo pacman -S nodejs npm

# Verify installation
node --version
npm --version
```

### 2. Clone or Copy the Project

```bash
git clone <your-repo-url> reaper-live-mixer
cd reaper-live-mixer

# Or if copying manually, navigate to the project folder
cd /path/to/Reaper_Live_Mixer
```

### 3. Install Dependencies

```bash
npm install
```

### 4. Configure Reaper

#### Copy the OSC Configuration File

```bash
# Create the OSC directory if it doesn't exist
mkdir -p ~/.config/REAPER/OSC

# Copy the pattern configuration
cp LiveMixer.ReaperOSC ~/.config/REAPER/OSC/
```

> **Note:** On some Linux distributions, Reaper config may be at `~/Library/Application Support/REAPER/OSC/` or check Reaper preferences for the actual path.

#### Set Up OSC in Reaper

1. Open Reaper
2. Go to **Preferences** → **Control/OSC/Web**
3. Click **Add**
4. Configure:
   - **Control surface mode:** OSC (Open Sound Control)
   - **Pattern config:** LiveMixer
   - **Device IP:** 127.0.0.1
   - **Device port:** 8000 (Reaper SENDS feedback to this port)
   - **Local listen port:** 9000 (Reaper RECEIVES commands on this port)
   - ☑️ **Allow binding messages to REAPER actions and FX learn**
5. Click **OK** and **Apply**

### 5. Install the FX Remote Script in Reaper

The FX parameters (EQ, Gate, Compressor) are controlled via a polling ReaScript, not OSC.

1. In Reaper, go to **Actions** → **Show action list**
2. Click **ReaScript** → **New ReaScript...**
3. Save the file as `FXRemote.lua` in your Reaper Scripts folder
4. Copy the contents of `FXRemote.lua` from this project into the script
5. Run the script (**Actions** → search for "FXRemote" → **Run**)

Alternatively, run directly:
1. **Actions** → **Show action list**
2. **ReaScript** → **Load ReaScript...**
3. Navigate to this project and select `FXRemote.lua`
4. Run the script

> **Important:** The FXRemote script must be running in Reaper for EQ and dynamics controls to work. You may want to add it to your project template or set it to run on startup.

### 6. Set Up Your Reaper Project

For the mixer to work correctly, your tracks should have FX in this order:

| FX Slot | Plugin | Purpose |
|---------|--------|---------|
| 0 | ReaGate | Noise gate |
| 1 | ReaComp | Compressor |
| 2 | ReaEQ | 4-band EQ + HPF |

For output/bus tracks, only ReaEQ at slot 0 is expected.

You can use the included `LIVE_MIXER_TEMPLATE.RPP` as a starting point, or set up your own project with the expected FX chain.

## Running the Mixer

### Start the Server

```bash
npm start
```

Or directly:

```bash
node server.js
```

You should see:

```
╔══════════════════════════════════════════════════════════════════════╗
║               REAPER LIVE MIXER - OSC BRIDGE SERVER                  ║
╠══════════════════════════════════════════════════════════════════════╣
║  Web Interface:    http://localhost:3000                             ║
║  OSC to Reaper:    127.0.0.1:9000                                    ║
║  OSC from Reaper:  listening on port 8000                            ║
╚══════════════════════════════════════════════════════════════════════╝
```

### Access the Mixer

Open a browser and navigate to:

```
http://localhost:3000
```

For tablets/phones on the same network:

```
http://<your-linux-machine-ip>:3000
```

## File Structure

| File | Purpose |
|------|---------|
| `server.js` | Node.js bridge server (WebSocket ↔ OSC) |
| `live_mixer_osc.html` | Main mixer web interface |
| `FXRemote.lua` | ReaScript for FX parameter control |
| `LiveMixer.ReaperOSC` | Reaper OSC pattern configuration |
| `DumpFXParams.lua` | Utility script to discover FX parameter indices |
| `LIVE_MIXER_TEMPLATE.RPP` | Example Reaper project template |

## Troubleshooting

### "Track 0 not found" errors
This was a bug with master track handling. Ensure you have the latest `FXRemote.lua` which uses `GetMasterTrack()` for track index 0.

### No fader movement in Reaper
- Check OSC is configured in Reaper preferences
- Verify ports match: server sends to 9000, receives on 8000
- Check firewall isn't blocking UDP ports

### EQ/Gate/Comp not responding
- Ensure `FXRemote.lua` is running in Reaper (check ReaScript console for "FXRemote: Started")
- Verify FX are in correct slots (Gate=0, Comp=1, EQ=2)
- Check `/tmp/fx_commands.txt` is writable

### Connection refused
- Make sure the server is running (`npm start`)
- Check if port 3000 is available: `lsof -i :3000`

### Finding FX Parameter Indices

Use the included `DumpFXParams.lua` script to discover parameter indices for different plugins:

1. Load the script in Reaper
2. Select a track with the FX you want to inspect
3. Run the script
4. Check the ReaScript console for parameter listings

## Network Access (Optional)

To access the mixer from other devices on your network:

```bash
# Find your IP address
ip addr show | grep "inet " | grep -v 127.0.0.1
```

Then access from any device on the same network at `http://<your-ip>:3000`

For persistent hosting, consider using a process manager:

```bash
# Install PM2
sudo npm install -g pm2

# Start the server
pm2 start server.js --name "reaper-mixer"

# Auto-start on boot
pm2 startup
pm2 save
```

## License

MIT
