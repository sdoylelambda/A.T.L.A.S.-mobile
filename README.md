## Mobile Client (Flutter)

Atlas is controllable from your phone over Tailscale.
The phone handles STT and TTS on-device — only text travels over the network.

### How it works
Phone speaks → STT → POST /command → Atlas computer
Atlas processes (full pipeline) → response text
Response text → Phone TTS speaks

### Computer setup (one time)

**1. Install dependencies**
```bash
pip install fastapi uvicorn qrcode Pillow --break-system-packages
```

**2. Generate API key**
```bash
openssl rand -hex 32 > ~/.config/atlas/api_key
chmod 600 ~/.config/atlas/api_key
```

**3. Get your Tailscale IP**
```bash
tailscale ip -4
```

**4. Start the API server**
```bash
cd ~/dev/A.T.L.A.S.
uvicorn api.fastapi_server:app --host 0.0.0.0 --port 8000
```

**5. Auto-start at boot (optional)**
```bash
sudo cp api/atlas-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable atlas-api
sudo systemctl start atlas-api
```

### Phone setup (one time)

**1. Install the app**
```bash
cd ~/dev/atlas_mobile
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

**2. Generate QR code for API key**
```bash
python3 ~/dev/A.T.L.A.S./api/gen_qr.py
```

**3. In the app**
- Open Atlas → tap Settings (gear icon)
- Server URL: `http://<tailscale-ip>:8000`
- API Key: tap QR icon → scan QR code on screen
- Tap Save

**4. Grant permissions on phone**
Settings → Apps → atlas_mobile → Permissions
→ Microphone → Allow
→ Camera → Allow  (for QR scanning)

### Wireless development
```bash
# connect phone wirelessly for cable-free flutter run
adb tcpip 5555
adb connect <phone-local-ip>:5555
flutter run
```

### Files added
A.T.L.A.S/
└── api/
├── fastapi_server.py     # FastAPI server
├── gen_qr.py             # API key QR generator
└── atlas-api.service     # systemd auto-start
atlas_mobile/
└── lib/
├── main.dart
├── screens/
│   ├── home_screen.dart
│   └── settings_screen.dart
└── services/
└── atlas_service.dart

### API endpoints
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/status` | None | Atlas running state |
| POST | `/command` | X-API-Key | Send command, get response |

### Roadmap
- Always-listen mode
- Response streaming (token by token)
- iOS support
- Push notifications for email alerts