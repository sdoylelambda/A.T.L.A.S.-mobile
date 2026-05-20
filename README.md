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

**1. Install Flutter and build the APK**
```bash
# install Flutter
sudo snap install flutter --classic
export PATH="$PATH:/home/$USER/snap/flutter/common/flutter/bin"
echo 'export PATH="$PATH:/home/$USER/snap/flutter/common/flutter/bin"' >> ~/.bashrc

# install Android SDK via Android Studio
sudo snap install android-studio --classic
# launch Android Studio once to complete SDK setup, then:
flutter config --android-sdk ~/Android/Sdk
flutter doctor --android-licenses  # accept all

# build APK
cd ~/dev/atlas_mobile
flutter pub get
flutter build apk --release

# install on phone (USB connected)
adb install build/app/outputs/flutter-apk/app-release.apk
```

**2. Generate QR code for API key**
```bash
python3 ~/dev/A.T.L.A.S./api/gen_qr.py
```

**3. Configure the app**
- Open Atlas mobile → tap Settings (gear icon)
- Server URL: `http://<tailscale-ip>:8000`
- API Key: tap QR icon → scan QR code on screen
- Tap Save

**4. Grant permissions on phone**
Settings → Apps → atlas_mobile → Permissions
→ Microphone → Allow
→ Camera → Allow

### Wireless development (no cable needed)
```bash
# with phone plugged in via USB first:
adb tcpip 5555
adb shell ip route | awk '{print $9}'  # get phone IP
adb connect <phone-ip>:5555
# unplug cable — flutter run now works over WiFi
flutter run
```

### Mobile app features
- Hold-to-speak orb with particle animation
- Full conversation history (slide-up drawer)
- Always-listen mode with auto-submit on silence
- Type commands via slide-up text field
- Cancel in-progress commands instantly
- Mute TTS independently
- QR code API key setup — no typing
- Orb states mirror desktop: listening / thinking / speaking / error / sleeping

### API endpoints
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/status` | None | Atlas running state |
| POST | `/command` | X-API-Key | Send command, get response |
| POST | `/cancel` | X-API-Key | Cancel current command |

### Security
- API key stored in `~/.config/atlas/api_key` (chmod 600, never in repo)
- Flutter stores credentials in Android Keystore via flutter_secure_storage
- All traffic encrypted by Tailscale
- Service runs as your user, not root