const scene = document.querySelector(".scene");
const timeDisplay = document.querySelector("#timeDisplay");
const statusKicker = document.querySelector("#statusKicker");
const modeCopy = document.querySelector("#modeCopy");
const focusHint = document.querySelector("#focusHint");
const startBtn = document.querySelector("#startBtn");
const resetBtn = document.querySelector("#resetBtn");
const skipBtn = document.querySelector("#skipBtn");
const roundsDone = document.querySelector("#roundsDone");
const streakLabel = document.querySelector("#streakLabel");
const ambientLabel = document.querySelector("#ambientLabel");
const soundToggle = document.querySelector("#soundToggle");
const progressRing = document.querySelector(".ring-progress");
const modeButtons = [...document.querySelectorAll(".mode")];
const durationInputs = [...document.querySelectorAll("[data-duration]")];

const modeDetails = {
  focus: {
    label: "focus",
    copy: "Deep work, soft pond energy.",
    hint: "One task. One pond. No rush.",
    next: "short",
  },
  short: {
    label: "breathe",
    copy: "Stretch, sip, blink at the sky.",
    hint: "Let the ripples flatten out.",
    next: "focus",
  },
  long: {
    label: "drift",
    copy: "A longer rest for a well-used brain.",
    hint: "You earned the wide water.",
    next: "focus",
  },
};

const state = {
  mode: "focus",
  running: false,
  remaining: 25 * 60,
  total: 25 * 60,
  completedFocus: 0,
  timerId: null,
  audioContext: null,
  soundTimer: null,
};

const ringLength = 2 * Math.PI * 104;
progressRing.style.strokeDasharray = ringLength;

function minutesFor(mode) {
  const input = document.querySelector(`[data-duration="${mode}"]`);
  return Math.max(1, Math.min(Number(input.value) || 1, Number(input.max)));
}

function formatTime(seconds) {
  const minutes = Math.floor(seconds / 60).toString().padStart(2, "0");
  const secs = Math.floor(seconds % 60).toString().padStart(2, "0");
  return `${minutes}:${secs}`;
}

function setMode(mode, preserveRunning = false) {
  state.mode = mode;
  state.total = minutesFor(mode) * 60;
  state.remaining = state.total;
  modeButtons.forEach((button) => {
    const active = button.dataset.mode === mode;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-selected", String(active));
  });
  statusKicker.textContent = modeDetails[mode].label;
  modeCopy.textContent = modeDetails[mode].copy;
  focusHint.textContent = modeDetails[mode].hint;
  if (!preserveRunning) stopTimer();
  render();
}

function render() {
  timeDisplay.textContent = formatTime(state.remaining);
  const elapsed = state.total - state.remaining;
  const progress = state.total > 0 ? elapsed / state.total : 0;
  progressRing.style.strokeDashoffset = ringLength * progress;
  roundsDone.textContent = state.completedFocus;
  streakLabel.textContent = state.completedFocus >= 4 ? "gliding" : state.running ? "steady" : "quiet";
  ambientLabel.textContent = soundToggle.checked ? "on" : "off";
  startBtn.querySelector("span:last-child").textContent = state.running ? "Pause" : "Start";
  startBtn.querySelector(".play-symbol").textContent = state.running ? "Ⅱ" : "▶";
  scene.classList.toggle("is-running", state.running);
  document.title = `${formatTime(state.remaining)} · Pond Timer`;
}

function startTimer() {
  if (state.running) return;
  state.running = true;
  playPondSound();
  state.timerId = window.setInterval(() => {
    state.remaining -= 1;
    if (state.remaining <= 0) {
      completeMode();
      return;
    }
    render();
  }, 1000);
  render();
}

function stopTimer() {
  state.running = false;
  window.clearInterval(state.timerId);
  state.timerId = null;
  stopPondSound();
  render();
}

function completeMode() {
  if (state.mode === "focus") state.completedFocus += 1;
  chime();
  const nextMode = state.mode === "focus" && state.completedFocus > 0 && state.completedFocus % 4 === 0
    ? "long"
    : modeDetails[state.mode].next;
  setMode(nextMode, true);
  if (state.running) startTimer();
}

function resetTimer() {
  state.remaining = state.total;
  stopTimer();
  render();
}

function skipTimer() {
  const nextMode = state.mode === "focus" && (state.completedFocus + 1) % 4 === 0 ? "long" : modeDetails[state.mode].next;
  setMode(nextMode);
}

function getAudioContext() {
  if (!state.audioContext) {
    state.audioContext = new AudioContext();
  }
  return state.audioContext;
}

function playTone(frequency, duration, type = "sine", volume = 0.05) {
  if (!soundToggle.checked) return;
  const ctx = getAudioContext();
  const oscillator = ctx.createOscillator();
  const gain = ctx.createGain();
  oscillator.type = type;
  oscillator.frequency.value = frequency;
  gain.gain.setValueAtTime(0.0001, ctx.currentTime);
  gain.gain.exponentialRampToValueAtTime(volume, ctx.currentTime + 0.03);
  gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + duration);
  oscillator.connect(gain);
  gain.connect(ctx.destination);
  oscillator.start();
  oscillator.stop(ctx.currentTime + duration + 0.02);
}

function playPondSound() {
  if (!soundToggle.checked || state.soundTimer) return;
  playTone(220, 0.18, "triangle", 0.025);
  state.soundTimer = window.setInterval(() => {
    if (!state.running) return;
    const note = 180 + Math.random() * 80;
    playTone(note, 0.16, "sine", 0.018);
  }, 5200);
}

function stopPondSound() {
  window.clearInterval(state.soundTimer);
  state.soundTimer = null;
}

function chime() {
  playTone(523.25, 0.16, "triangle", 0.06);
  window.setTimeout(() => playTone(659.25, 0.2, "triangle", 0.05), 150);
  window.setTimeout(() => playTone(783.99, 0.24, "triangle", 0.045), 310);
}

startBtn.addEventListener("click", () => {
  state.running ? stopTimer() : startTimer();
});

resetBtn.addEventListener("click", resetTimer);
skipBtn.addEventListener("click", skipTimer);

modeButtons.forEach((button) => {
  button.addEventListener("click", () => setMode(button.dataset.mode));
});

durationInputs.forEach((input) => {
  input.addEventListener("change", () => {
    input.value = Math.max(1, Math.min(Number(input.value) || 1, Number(input.max)));
    if (input.dataset.duration === state.mode) setMode(state.mode);
  });
});

soundToggle.addEventListener("change", () => {
  if (!soundToggle.checked) stopPondSound();
  if (soundToggle.checked && state.running) playPondSound();
  render();
});

setMode("focus");
