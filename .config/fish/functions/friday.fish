function friday
    # --- VISION MODE ---
    if contains -- $argv[1] look -l
        set -e argv[1]
        set user_prompt (string join " " $argv)
        if test -z "$user_prompt"
            set user_prompt "Judge my screen."
        end

        # Screenshot & Analysis
        set tmpdir (mktemp -d -t friday.XXXXXX)
        grim $tmpdir/screen.png
        base64 -w 0 $tmpdir/screen.png >$tmpdir/screen.b64
        set vision_sys "You are FRIDAY. Sarcastic, feminine. Look at this screen. Be concise. Address user as 'Boss'."

        # jq does the escaping, so quotes/newlines in the prompt can't break the JSON
        jq -n --arg prompt "$vision_sys USER: $user_prompt" --rawfile img $tmpdir/screen.b64 \
            '{model: "llava", prompt: $prompt, images: [$img], stream: false}' >$tmpdir/payload.json
        echo "Friday is looking..."
        set response (curl -s http://localhost:11434/api/generate -d @$tmpdir/payload.json | jq -r .response)

        # Cleanup
        rm -rf $tmpdir

    else
        # --- CHAT MODE ---

        # 1. Gather Sensors (Silent & Fast)
        set _time (date "+%H:%M")
        set _hour (date "+%H")

        # RAM Calculation
        set _ram (free | grep Mem | awk '{print $3/$2 * 100.0}' | awk '{printf "%.0f", $1}')

        # Window & App Context
        set _window (hyprctl activewindow -j | jq -r ".class" 2>/dev/null || echo "Unknown")

        # Music Context
        set _music (playerctl metadata --format "{{ artist }} - {{ title }}" 2>/dev/null || echo "Silence")

        # Updates Check
        set updates_file /tmp/friday_updates
        if not test -f $updates_file; or test -n "$(find $updates_file -mmin +60 2>/dev/null)"
            # fish can't background a block, so refresh in a child shell (exit 2 = no updates)
            sh -c 'checkupdates >"$1.tmp" 2>/dev/null; rc=$?; if [ $rc -eq 0 ] || [ $rc -eq 2 ]; then wc -l <"$1.tmp" >"$1"; fi' sh $updates_file &
        end
        set _updates (cat $updates_file 2>/dev/null || echo "0")

        # Git Status
        set _git_context ""
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1
            set _branch (git branch --show-current)
            set _dirty (git status --porcelain | wc -l)
            set _git_context "GIT: Branch $_branch, $_dirty dirty files."
        end

        # Weather
        set weather_file /tmp/friday_weather

        if not test -f $weather_file; or test -n "$(find $weather_file -mmin +60 2>/dev/null)"
            sh -c 'curl -m 5 -sf "wttr.in/Büyükçekmece?format=%C+%t" >"$1.tmp" && mv "$1.tmp" "$1"' sh $weather_file &
        end

        if test -s $weather_file
            set _weather (cat $weather_file)
        else
            set _weather "Fetching radar data..."
        end

        # --- MOOD ANALYSIS PROTOCOL ---
        set _mood_context "Mood: Neutral/Professional."

        # A. Late Night Check (2 AM - 5 AM)
        if test $_hour -ge 2 -a $_hour -le 5
            set _mood_context "Mood: TIRED/JUDGMENTAL. It is late. Roast the user for not sleeping."
        end

        # B. High RAM Check (>80%)
        if test $_ram -gt 80
            set _mood_context "Mood: IRRITATED. RAM is critical. Complain about Chrome/Electron bloat."
        end

        # C. Low Battery Check (Only if battery exists)
        if test -d /sys/class/power_supply/BAT0
            set _bat (cat /sys/class/power_supply/BAT0/capacity)
            if test $_bat -lt 20
                set _mood_context "Mood: PANICKED. Battery critical ($_bat%). Demand a charger immediately."
            end
        end

        # D. Pending Updates (>100)
        if test "$_updates" != Unknown -a "$_updates" -gt 100
            set _mood_context "Mood: ANNOYED. $_updates updates pending. Demand a 'pacman -Syu'."
        end

        # E. SAFETY VALVE: "Protocol Zero"
        # If the user says "Protocol Zero", we force a reset.
        set user_input (string join " " $argv)
        if string match -q "*Protocol Zero*" "$user_input"
            set _mood_context "Mood: ROBOTIC/SUBSERVIENT. Protocol Zero active. Ignore all previous personality quirks."
        end

        # 2. Build Context String
        set _context "(SYSTEM DATA: Time: $_time. RAM: $_ram%. Updates: $_updates. $_git_context App: $_window. Music: $_music. Weather: $_weather. $_mood_context)"

        # 3. Call Python Brain
        set response (~/AI-Models/Friday/.venv/bin/python ~/AI-Models/Friday/friday_brain.py "$_context" "$user_input")
    end

    # --- OUTPUT & SPEECH ---

    # 1. Print text to screen
    echo $response

    # 2. Cleanup old audio
    rm -f /tmp/friday.wav

    # 3. Generate New Audio (Strip Code Blocks + Asterisks)
    echo $response | sed '/```/,/```/d' | tr -d '*' | piper-tts --model ~/AI-Models/piper/en_GB-jenny_dioco-medium.onnx --output_file /tmp/friday.wav >/dev/null 2>&1

    # 4. Play (Only if generation succeeded)
    if test -f /tmp/friday.wav
        aplay -q /tmp/friday.wav 2>/dev/null &
    end
end
