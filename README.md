# BirbAlert
Bird call detection and notification device

## About
I designed this BirbAlert system as an anniversary gift for my wife, who loves spotting interesting birds in our neighborhood. She has been staying at home watching our toddler son and doesn't get to enjoy as much time drinking coffee on the porch as she would like, and when she does there is usually someone else there screaming and scaring off the birds. I wanted to help her optimize her trips to the porch so she can have a better chance of spotting something fun when she does go outside. <br>
BirbAlert is installed on a raspberry pi with a microphone attached and mounted on our porch. It listens continuously and analyzes the recordings to identify bird calls. Whenever an interesting bird is detected, it sends a message to our Home Assistant, which then sends a notification to her phone so she can run outside and spot the bird.

## Project Plan
### Order Parts
#### CanaKit - $138.80

- [x]  Raspberry Pi 4 Model B (4GB RAM)
- [x]  Official Raspberry Pi USB-C Power Supply (5V, 3A)
- [x]  Raspberry Pi Case
- [x]  32–64GB microSD card (Class 10) - Samsung EVO, SanDisk Extreme

#### Sonorous Objects - $116.21

- [x]  Mic
    - [x]  SO.1 Omni Microphone (uses Primo EM272)
- [x]  Foam microphone windscreen
- [x]  Shielded 3.5mm audio extension cable

#### Sabrent - $8.99

- [x]  USB Audio Adapter with Mic Input - Sabrent USB External Sound Adapter

#### Home Depot

- [ ]  Rubber grommet
- [ ]  Exterior-grade silicone sealant

---

### Raspberry Pi Setup
#### Steps

1. Install Raspberry Pi OS Lite (64-bit)
2. Enable SSH
3. Set hostname (e.g., `birdnet-pi`)
4. Set static IP or DHCP reservation
5. Update system packages

#### Exit criteria

- SSH access working
- Network stable
- Pi reachable from Home Assistant

---

### Validate Audio
### Steps

1. Identify audio device (`arecord -l`)
2. Set mic gain using `alsamixer`
3. Record test clips (3–5 seconds)
4. Listen with headphones
5. Adjust placement or gain if needed

### Exit criteria

- Bird calls clearly audible
- No clipping
- Minimal wind noise

#### Implementation
**Confirm audio is working**

aplay -l (list devices)

arecord -D plughw:3,0 -f S16_LE -r 48000 -c 1 -d 10 /tmp/test.wav (record sample on saramonic mic) 

aplay -D plughw:0,0 /tmp/test.wav (play sample on headphones)

---


### Install BirdNet Model
#### Steps

1. Install Python + dependencies
2. Clone BirdNET-Analyzer repository
3. Download pretrained model
4. Run BirdNET on saved test WAVs
5. Review output confidence and species

#### Exit criteria

- BirdNET correctly identifies common birds
- Runtime acceptable (< ~5s per clip)

#### Implementation

**Docker Setup**

- Installed Docker via the official script.
- Logged out/in to apply Docker group changes.
- Verified Docker installation.

sudo apt update
sudo apt install -y docker.io
sudo usermod -aG docker $USER
sudo reboot
docker run hello-world

**BirdNET Analyzer Setup**

- Cloned the **BirdNET-Analyzer** repository.
- Built the **Docker image (`birdnet-pi`)** successfully.
- Confirmed the image exists with `docker images`.

cd ~
git clone https://github.com/kahst/BirdNET-Analyzer.git
cd BirdNET-Analyzer
docker build -t birdnet-pi .

mkdir -p ~/birdnet_recordings
mkdir -p ~/birdnet_logs

**4. USB Audio Device Detection**

- Verified the USB audio adapter is detected by ALSA (`card 1, device 0`).
- Tested recording with `arecord` — created WAV files without errors (even though no mic was plugged in).
- Verified the recording file exists and is non-empty.

**5. Docker + Audio Pipeline**

- Learned that BirdNET Docker container doesn’t need ALSA — we record on the host and feed WAV files to Docker.
- Figured out correct Docker commands:
    - Overriding the image’s entrypoint to run Python: `-entrypoint python`
    - Using positional argument for input audio and `o` for output.
- Ran the first analysis command (error-free CLI; now ready to process audio).
- Verified ~24 GB free space — plenty for Docker and BirdNET.

**Confirm analyzer is working**

mv /tmp/test.wav ~/birdnet_recordings/ (move file)

docker run --rm \
--entrypoint python \
-v ~/birdnet_recordings:/recordings \
-v ~/birdnet_logs:/logs \
birdnet-pi -m birdnet_analyzer.analyze \
/recordings/test.wav -o /logs --rtype csv --min_conf 0.1

ls -lh ~/birdnet_logs/ (view output files)
cat ~/birdnet_logs/test.BirdNET.results.csv (view output)

---


### Write Detection Loop
#### Steps

1. Write recording script (fixed-length WAVs)
2. Integrate BirdNET inference
3. Parse results into structured output
4. Log detections to file
5. Auto-delete processed audio

#### Exit criteria

- Loop runs unattended for 1+ hour
- No memory or disk growth
- Logs show reasonable detections

#### Implementation

*Commands*
nano ~/birdnet_loop.sh (create script)
chmod +x ~/birdnet_loop.sh (make script executable)
nohup ~/birdnet_loop.sh > ~/birdnet.log 2>&1 & (run script)
tail -f ~/birdnet.log (check logs)
pkill -f birdnet_loop.sh (kill script)


**Continuous Recording Script**

We created a loop script: `~/birdnet_loop.sh`

*Features:*

- Records fixed-length WAVs from the USB microphone:

```
arecord-D"$MIC_DEVICE"-fcd-d"$DURATION""$FILE"
```

- Runs **BirdNET analysis** via Docker:

```
docker run--rm \
--entrypoint python \
-v"$RECORD_DIR":/recordings \
-v"$LOG_DIR":/logs \
    birdnet-pi \
-m birdnet_analyzer.analyze /recordings/$(basename"$FILE") \
-o /logs \
--min_conf"$MIN_CONF" \
--rtype csv
```

- Moves processed audio to a separate folder:

```
mv"$FILE""$PROCESSED_DIR/"
```

- Deletes old processed audio automatically:

```
find"$PROCESSED_DIR"-type f-name"*.wav"-mmin+"$AUDIO_RETENTION_MIN"-execrm {} \;
```

- Merges all CSV logs into a single `combined_results.csv`:

```
for fin"$LOG_DIR"/*.csv;do
    tail-n+2"$f" >>"$MERGED_LOG"2>/dev/null
done
```

- Archives old CSV logs to `archive/` folder:

```
find"$LOG_DIR"-type f-name"*.csv" !-name"$(basename$MERGED_LOG)"-mtime+"$LOG_RETENTION_DAYS"-execmv {}"$ARCHIVE_DIR/" \;
```

- Handles **graceful shutdown** via `trap` for `SIGINT`/`SIGTERM`.


**2 Systemd Service Setup**

We created a **BirdNET systemd service**: `/etc/systemd/system/birdnet.service`

*Contents:*

```
[Unit]
Description=BirdNET Continuous Detection
After=network.target

[Service]
Type=simple
User=user_name
WorkingDirectory=/home/user_name
ExecStart=/home/user_name/birdnet_loop.sh
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

*Key points:*

- Single `ExecStart=` points to the loop script (systemd error fixed).
- Automatic restart if the service fails.
- Logs are captured by `journalctl`.
- Service enabled to start on boot:

```
sudo systemctl daemon-reload
sudo systemctl enable birdnet
sudo systemctlstart birdnet
```

**3 Logging and Cleanup Features**

- **Audio cleanup:** removes processed audio older than 1 hour.
- **CSV rotation:** moves individual CSV logs older than 7 days to `archive/`.
- **Merged CSV:** keeps one `combined_results.csv` for easy review.
- **Optional improvements:** daily CSV rotation, size-based splitting, remote backup.

**4 Verification Steps**

- Check that recording & analysis runs continuously:

```
journalctl-u birdnet-f
```

- Check merged CSV:

```
cat ~/birdnet_logs/combined_results.csv | head
```

- Confirm audio cleanup:

```
ls ~/birdnet_processed
```

- Confirm CSV archiving:

```
ls ~/birdnet_logs/archive
```

- Monitor system resource usage:

```
htop
df-h
```

---

### Write Filtering Rules
#### Steps

1. Create `config.yaml`
    - Interesting birds
    - Min confidence
    - Cooldown duration
2. Implement whitelist filtering
3. Implement per-species cooldown
4. Test with real detections

#### Exit criteria

- No repeated alerts for same species
- Confidence threshold feels right

---

### Integrate Home Assistant
## Phase 7 — Home Assistant Integration

**Goal:** Phone notifications via HA.

#### Steps

1. Create Home Assistant webhook
2. Create automation tied to webhook
3. Send test payload manually
4. Integrate webhook call into detection script
5. Tune notification message format

#### Exit criteria

- Phone receives test notification
- Real detections trigger alerts

---

### QA
#### Steps

1. Run detection loop as systemd service
2. Enable auto-restart on failure
3. Rotate logs
4. Add basic error handling
5. Reboot test

### Exit criteria

- Service starts on boot
- Survives mic disconnects or errors

---

## Phase 9 — Environmental Tuning

**Goal:** Reduce false positives.

#### Steps

1. Add quiet hours (optional)
2. Add RMS noise threshold (wind/rain skip)
3. Adjust confidence thresholds
4. Review logs after several days

#### Exit criteria

- Low false-positive rate
- Notifications feel “special,” not noisy

---

## Enhancements (Optional)

**Goal:** Polish and expand.

#### Ideas

- Save clips for interesting birds only
- Attach audio clip to HA notification
- Daily summary sensor in HA
- Multiple microphones
- Seasonal bird lists


