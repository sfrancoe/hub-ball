const response = await fetch('../../data/tolle-immaculate.json');
if (!response.ok) throw new Error('Could not load the immaculate-inning data.');
const inning = await response.json();

const pitches = document.getElementById('pitches');
const pitchCount = document.getElementById('pitchCount');
const moment = document.getElementById('moment');
const play = document.getElementById('play');
const restart = document.getElementById('restart');
let shown = 0;
let timer;

document.getElementById('gameContext').textContent =
  `${inning.date} · ${inning.opponent} at Boston · ${inning.final_score}`;
document.getElementById('mlbSource').href = `https://www.mlb.com/gameday/${inning.game_pk}`;

for (const pitch of inning.pitches) {
  const item = document.createElement('li');
  item.className = 'pitch';
  item.innerHTML = `<span class="pitch-number">PITCH ${pitch.number}</span><strong class="pitch-speed">${pitch.speed.toFixed(1)}</strong><span class="pitch-type">${pitch.pitch_type}</span><span class="batter">${pitch.batter}</span>`;
  pitches.appendChild(item);
}

function render() {
  [...pitches.children].forEach((item, index) => item.classList.toggle('active', index < shown));
  pitchCount.textContent = shown;
  if (shown === 0) moment.textContent = 'Press play to take the inning one pitch at a time.';
  else if (shown < 9) moment.textContent = `${inning.pitches[shown - 1].description}. ${inning.pitches[shown - 1].batter} is down.`;
  else moment.textContent = 'Nine pitches. Nine strikes. Three strikeouts. Immaculate.';
}

function stop() { window.clearInterval(timer); timer = undefined; play.textContent = shown === 9 ? '▶ Replay the inning' : '▶ Continue'; }
function advance() { shown += 1; render(); if (shown === 9) stop(); }
function start() { if (shown === 9) shown = 0; render(); stop(); play.textContent = 'Playing…'; advance(); timer = window.setInterval(advance, 800); }
play.addEventListener('click', start);
restart.addEventListener('click', () => { stop(); shown = 0; render(); play.textContent = '▶ Replay the inning'; });
render();
