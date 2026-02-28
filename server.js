/**
 * Reaper Live Mixer - OSC Bridge Server
 * 
 * This server bridges WebSocket connections from the web interface
 * to OSC for controlling Reaper FX parameters.
 * 
 * Setup in Reaper:
 * 1. Preferences → Control/OSC/Web → Add
 * 2. Control surface mode: OSC (Open Sound Control)
 * 3. Device IP: 127.0.0.1
 * 4. Device port: 9000 (where we send TO Reaper)
 * 5. Local listen port: 8000 (where Reaper sends feedback TO us)
 */

const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const osc = require('osc');
const path = require('path');
const fs = require('fs');
const os = require('os');

// FX Command file path (where ReaScript reads commands)
// Use /tmp for simplicity on Mac/Linux
const FX_CMD_FILE = '/tmp/fx_commands.txt';
const FX_RESPONSE_FILE = '/tmp/fx_response.txt';

// Configuration
const CONFIG = {
  webPort: 3000,           // Web server port (access mixer at http://localhost:3000)
  reaperOscPort: 9000,     // Port to send OSC to Reaper
  reaperOscHost: '127.0.0.1',
  localOscPort: 8000,      // Port to receive OSC from Reaper
};

// Create Express app
const app = express();
const server = http.createServer(app);

// Serve static files
app.use(express.static(__dirname));

// Serve the mixer page
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'live_mixer_osc.html'));
});

// Create WebSocket server
const wss = new WebSocket.Server({ server, path: '/osc' });

// Create UDP port for OSC
const udpPort = new osc.UDPPort({
  localAddress: '0.0.0.0',
  localPort: CONFIG.localOscPort,
  remoteAddress: CONFIG.reaperOscHost,
  remotePort: CONFIG.reaperOscPort,
  metadata: true
});

// Track connected WebSocket clients
const clients = new Set();

// Handle WebSocket connections
wss.on('connection', (ws) => {
  console.log('Web client connected');
  clients.add(ws);
  
  // Request initial state from Reaper
  requestFullRefresh();
  
  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);
      handleWebMessage(data);
    } catch (e) {
      console.error('Invalid WebSocket message:', e);
    }
  });
  
  ws.on('close', () => {
    console.log('Web client disconnected');
    clients.delete(ws);
  });
});

// Handle messages from web client
function handleWebMessage(data) {
  if (data.type === 'osc') {
    // Forward OSC message to Reaper
    const oscMessage = {
      address: data.address,
      args: data.args || []
    };
    
    console.log('→ Reaper:', oscMessage.address, oscMessage.args);
    udpPort.send(oscMessage);
  } else if (data.type === 'refresh') {
    requestFullRefresh();
  } else if (data.type === 'fx') {
    // Write FX command to file for ReaScript to process
    const { trackIdx, fxIdx, paramIdx, value } = data;
    const cmd = `${trackIdx},${fxIdx},${paramIdx},${value}\n`;
    
    try {
      fs.appendFileSync(FX_CMD_FILE, cmd);
      console.log('→ FX:', cmd.trim());
    } catch (e) {
      console.error('FX command file error:', e.message);
    }
  } else if (data.type === 'fxBypass') {
    // Write bypass toggle command
    const { trackIdx, fxIdx } = data;
    const cmd = `B,${trackIdx},${fxIdx}\n`;
    
    try {
      fs.writeFileSync(FX_RESPONSE_FILE, '');
      fs.appendFileSync(FX_CMD_FILE, cmd);
      console.log('→ FX Bypass:', cmd.trim());
      
      // Poll for response with new bypass state
      let attempts = 0;
      const pollInterval = setInterval(() => {
        attempts++;
        try {
          const response = fs.readFileSync(FX_RESPONSE_FILE, 'utf8');
          if (response && response.trim()) {
            clearInterval(pollInterval);
            fs.writeFileSync(FX_RESPONSE_FILE, '');
            
            const lines = response.trim().split('\n');
            const fxData = { type: 'fxValues', trackIdx, params: [], bypassed: {} };
            
            lines.forEach(line => {
              const parts = line.split(',');
              if (parts[0] === 'E') {
                fxData.bypassed[parts[2]] = parts[3] === '0';
              }
            });
            
            clients.forEach(client => {
              if (client.readyState === WebSocket.OPEN) {
                client.send(JSON.stringify(fxData));
              }
            });
            console.log('← FX Bypass state updated');
          }
        } catch (e) {}
        
        if (attempts > 10) {
          clearInterval(pollInterval);
        }
      }, 50);
    } catch (e) {
      console.error('FX command file error:', e.message);
    }
  } else if (data.type === 'fxReadOutput') {
    // Request output EQ values (only FX slot 0 = ReaEQ)
    const { trackIdx } = data;
    const cmd = `O,${trackIdx}\n`;
    
    try {
      fs.writeFileSync(FX_RESPONSE_FILE, '');
      fs.appendFileSync(FX_CMD_FILE, cmd);
      console.log('→ FX Read Output:', cmd.trim());
      
      let attempts = 0;
      const pollInterval = setInterval(() => {
        attempts++;
        try {
          const response = fs.readFileSync(FX_RESPONSE_FILE, 'utf8');
          if (response && response.trim()) {
            clearInterval(pollInterval);
            fs.writeFileSync(FX_RESPONSE_FILE, '');
            
            const lines = response.trim().split('\n');
            const fxData = { type: 'fxValues', trackIdx, params: [], bypassed: {} };
            
            lines.forEach(line => {
              const parts = line.split(',');
              if (parts[0] === 'P') {
                fxData.params.push({
                  fxIdx: parseInt(parts[2]),
                  paramIdx: parseInt(parts[3]),
                  value: parseFloat(parts[4])
                });
              } else if (parts[0] === 'E') {
                fxData.bypassed[parts[2]] = parts[3] === '0';
              }
            });
            
            clients.forEach(client => {
              if (client.readyState === WebSocket.OPEN) {
                client.send(JSON.stringify(fxData));
              }
            });
          }
        } catch (e) {}
        if (attempts > 20) clearInterval(pollInterval);
      }, 50);
    } catch (e) {
      console.error('FX read output error:', e.message);
    }
  } else if (data.type === 'sendsReadAll') {
    // Request ALL send values at once from ReaScript
    const cmd = `SENDS\n`;
    
    try {
      fs.writeFileSync(FX_RESPONSE_FILE, '');
      fs.appendFileSync(FX_CMD_FILE, cmd);
      console.log('→ Sends Read All');
      
      let attempts = 0;
      const pollInterval = setInterval(() => {
        attempts++;
        try {
          const response = fs.readFileSync(FX_RESPONSE_FILE, 'utf8');
          if (response && response.trim()) {
            clearInterval(pollInterval);
            fs.writeFileSync(FX_RESPONSE_FILE, '');
            
            const lines = response.trim().split('\n');
            // Group sends by trackIdx
            const sendsByTrack = {};
            
            lines.forEach(line => {
              const parts = line.split(',');
              if (parts[0] === 'S') {
                // S,trackIdx,sendIdx,vol
                const trackIdx = parseInt(parts[1]);
                const sendIdx = parseInt(parts[2]);
                const vol = parseFloat(parts[3]);
                
                if (!sendsByTrack[trackIdx]) {
                  sendsByTrack[trackIdx] = [];
                }
                sendsByTrack[trackIdx].push({ sendIdx, vol });
              }
            });
            
            // Send all data at once
            const sendData = { type: 'allSendValues', tracks: sendsByTrack };
            
            clients.forEach(client => {
              if (client.readyState === WebSocket.OPEN) {
                client.send(JSON.stringify(sendData));
              }
            });
            console.log('← All Send Values:', Object.keys(sendsByTrack).length, 'tracks');
          }
        } catch (e) {}
        if (attempts > 20) clearInterval(pollInterval);
      }, 50);
    } catch (e) {
      console.error('Sends read error:', e.message);
    }
  } else if (data.type === 'fxRead') {
    // Request FX values from ReaScript
    const { trackIdx, ws: clientWs } = data;
    const cmd = `R,${trackIdx}\n`;
    
    try {
      // Clear response file first
      fs.writeFileSync(FX_RESPONSE_FILE, '');
      fs.appendFileSync(FX_CMD_FILE, cmd);
      console.log('→ FX Read:', cmd.trim());
      
      // Poll for response (ReaScript will write to response file)
      let attempts = 0;
      const pollInterval = setInterval(() => {
        attempts++;
        try {
          const response = fs.readFileSync(FX_RESPONSE_FILE, 'utf8');
          if (response && response.trim()) {
            clearInterval(pollInterval);
            // Clear the response file
            fs.writeFileSync(FX_RESPONSE_FILE, '');
            
            // Parse and send to clients
            const lines = response.trim().split('\n');
            const fxData = { type: 'fxValues', trackIdx, params: [], bypassed: {} };
            
            lines.forEach(line => {
              const parts = line.split(',');
              if (parts[0] === 'P') {
                // P,trackIdx,fxIdx,paramIdx,value
                fxData.params.push({
                  fxIdx: parseInt(parts[2]),
                  paramIdx: parseInt(parts[3]),
                  value: parseFloat(parts[4])
                });
              } else if (parts[0] === 'E') {
                // E,trackIdx,fxIdx,enabled
                fxData.bypassed[parts[2]] = parts[3] === '0';
              }
            });
            
            // Send to all clients
            clients.forEach(client => {
              if (client.readyState === WebSocket.OPEN) {
                client.send(JSON.stringify(fxData));
              }
            });
            console.log('← FX Values:', fxData.params.length, 'params');
          }
        } catch (e) {
          // File not ready yet
        }
        
        if (attempts > 20) { // 1 second timeout
          clearInterval(pollInterval);
          console.log('FX Read timeout');
        }
      }, 50);
    } catch (e) {
      console.error('FX read error:', e.message);
    }
  }
}

// Request full state refresh from Reaper
function requestFullRefresh() {
  // Request track info for first 32 tracks
  for (let i = 1; i <= 32; i++) {
    udpPort.send({ address: `/track/${i}/volume`, args: [] });
    udpPort.send({ address: `/track/${i}/pan`, args: [] });
    udpPort.send({ address: `/track/${i}/mute`, args: [] });
    udpPort.send({ address: `/track/${i}/solo`, args: [] });
    udpPort.send({ address: `/track/${i}/name`, args: [] });
  }
}

// Handle OSC messages from Reaper
udpPort.on('message', (oscMsg) => {
  console.log('← Reaper:', oscMsg.address, oscMsg.args);
  
  // Broadcast to all connected web clients
  const message = JSON.stringify({
    type: 'osc',
    address: oscMsg.address,
    args: oscMsg.args
  });
  
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
});

// Handle OSC errors
udpPort.on('error', (err) => {
  console.error('OSC Error:', err);
});

// Open the OSC port
udpPort.open();

udpPort.on('ready', () => {
  console.log(`
╔══════════════════════════════════════════════════════════════════════╗
║               REAPER LIVE MIXER - OSC BRIDGE SERVER                  ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  Web Interface:    http://localhost:${CONFIG.webPort}                           ║
║  OSC to Reaper:    ${CONFIG.reaperOscHost}:${CONFIG.reaperOscPort}                               ║
║  OSC from Reaper:  listening on port ${CONFIG.localOscPort}                          ║
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║  REAPER SETUP - ONE-TIME:                                            ║
║                                                                      ║
║  1. Copy LiveMixer.ReaperOSC to:                                     ║
║     Mac:  ~/Library/Application Support/REAPER/OSC/                  ║
║     Win:  %APPDATA%\\REAPER\\OSC\\                                     ║
║                                                                      ║
║  2. In Reaper → Preferences → Control/OSC/Web → Add:                 ║
║     • Mode: OSC (Open Sound Control)                                 ║
║     • Pattern config: LiveMixer                                      ║
║     • Device IP: 127.0.0.1                                           ║
║     • Device port: ${CONFIG.localOscPort}  (Reaper SENDS to our bridge)            ║
║     • Local listen port: ${CONFIG.reaperOscPort}  (Reaper RECEIVES from us)           ║
║     • ✓ Allow binding messages to REAPER actions and FX learn        ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
  `);
});

// Start web server
server.listen(CONFIG.webPort, () => {
  console.log(`Web server running on port ${CONFIG.webPort}`);
});
