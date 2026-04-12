let TILES_DIR = 'tiles/monthly';
const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

let months = [];
let currentIndex = 0;
let playing = false;
let playInterval = null;
const PREBUFFER_FRAMES = 10;
let PLAY_SPEED_MS = 1000;
let layerStates = [];

// --- PMTiles protocol ---

const pmtilesProtocol = new pmtiles.Protocol({ metadata: true });
maplibregl.addProtocol('pmtiles', pmtilesProtocol.tile);

// --- Map ---

const map = new maplibregl.Map({
  container: 'map',
  style: {
    version: 8,
    sources: {
      'carto-dark': {
        type: 'raster',
        tiles: ['https://a.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}@2x.png'],
        tileSize: 256,
        attribution: '&copy; CARTO &copy; OpenStreetMap contributors'
      },
      'esri-satellite': {
        type: 'raster',
        tiles: ['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],
        tileSize: 256,
        attribution: '&copy; Esri, Maxar, Earthstar Geographics'
      }
    },
    layers: [{
      id: 'carto-dark',
      type: 'raster',
      source: 'carto-dark'
    }, {
      id: 'esri-satellite',
      type: 'raster',
      source: 'esri-satellite',
      layout: { 'visibility': 'none' }
    }]
  },
  center: [20, 35],
  zoom: 2,
  maxZoom: 16,
  attributionControl: false
});

map.addControl(new maplibregl.AttributionControl({ compact: true }), 'bottom-right');
map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');

// --- Load metadata and init ---

async function init() {
  // Load config
  try {
    const configResp = await fetch('config.json');
    const config = await configResp.json();
    TILES_DIR = config.tilesDir || TILES_DIR;
    document.querySelector('h1').innerHTML = config.title || 'NO<sub>2</sub> Timelapse';
    document.querySelector('.subtitle').textContent = config.subtitle || '';
    const isRolling = (config.tilesDir || '').includes('rolling');
    document.getElementById('mode-note').textContent = isRolling
      ? 'Showing 12-month rolling mean'
      : 'Showing individual monthly data';
  } catch (e) {
    console.warn('Could not load config.json, using defaults');
  }

  try {
    const resp = await fetch(`${TILES_DIR}/metadata.json`);
    const meta = await resp.json();
    months = meta.months;
  } catch (e) {
    console.warn('Could not load metadata.json, scanning for tiles...');
    months = [];
  }

  if (months.length === 0) {
    document.getElementById('month-label').textContent = 'No data available';
    return;
  }

  // Setup timeline slider
  const n = months.length;
  const timeline = document.getElementById('timeline');
  timeline.max = n - 1;
  timeline.value = 0;
  
  // Reset playback speed to default on page reload to prevent browser caching stale values
  document.getElementById('speed-select').value = '1000';
  PLAY_SPEED_MS = 1000;

  // Align slider thumb (14px wide) to perfectly match the start of each buffer segment
  timeline.style.left = '-7px';
  timeline.style.width = `calc(100% * ${n - 1} / ${n} + 14px)`;

  // Setup buffer indicator segments
  const bufferContainer = document.getElementById('timeline-buffer');
  bufferContainer.innerHTML = '';
  months.forEach((_, i) => {
    const seg = document.createElement('div');
    seg.className = 'timeline-buffer-segment';
    seg.id = `buffer-segment-${i}`;
    bufferContainer.appendChild(seg);
  });

  map.on('load', () => {
    // Add all monthly NO2 sources and layers upfront for smooth switching
    months.forEach((month, i) => {
      map.addSource(`no2-${i}`, {
        type: 'raster',
        url: pmtilesUrl(i),
        tileSize: 256
      });

      map.addLayer({
        id: `no2-layer-${i}`,
        type: 'raster',
        source: `no2-${i}`,
        maxzoom: 10,
        layout: { 'visibility': i === 0 ? 'visible' : 'none' },
        paint: {
          'raster-opacity': 0.6,
          'raster-opacity-transition': { duration: 0 },
          'raster-fade-duration': 0
        }
      });
    });

    // Cities layer — sync visibility with checkbox state (browser may remember it across reloads)
    const citiesVis = document.getElementById('toggle-cities').checked ? 'visible' : 'none';

    map.addSource('cities', {
      type: 'geojson',
      data: 'data/cities.geojson'
    });

    map.addLayer({
      id: 'cities-labels',
      type: 'symbol',
      source: 'cities',
      layout: {
        'text-field': ['get', 'name'],
        'text-size': [
          'interpolate', ['linear'], ['zoom'],
          2, ['case', ['>=', ['get', 'population'], 5000000], 22, 0],
          4, ['case', ['>=', ['get', 'population'], 1000000], 22, 0],
          6, ['case', ['>=', ['get', 'population'], 500000], 20, 0],
          8, 10
        ],
        'text-anchor': 'left',
        'text-offset': [0.8, 0],
        'text-max-width': 8,
        'text-allow-overlap': false,
        'visibility': citiesVis
      },
      paint: {
        'text-color': '#ffffff',
        'text-halo-color': 'rgba(0,0,0,0.8)',
        'text-halo-width': 1.5
      }
    });

    // Outer glow ring
    map.addLayer({
      id: 'cities-glow',
      type: 'circle',
      source: 'cities',
      layout: { 'visibility': citiesVis },
      paint: {
        'circle-radius': [
          'interpolate', ['linear'], ['zoom'],
          2, ['case', ['>=', ['get', 'population'], 5000000], 10, 0],
          4, ['case', ['>=', ['get', 'population'], 1000000], 9, 0],
          6, ['case', ['>=', ['get', 'population'], 500000], 8, 0],
          8, 7
        ],
        'circle-color': '#8ab4f8',
        'circle-opacity': 0.15,
        'circle-blur': 1
      }
    });

    // Dot
    map.addLayer({
      id: 'cities-dots',
      type: 'circle',
      source: 'cities',
      layout: { 'visibility': citiesVis },
      paint: {
        'circle-radius': [
          'interpolate', ['linear'], ['zoom'],
          2, ['case', ['>=', ['get', 'population'], 5000000], 3, 0],
          4, ['case', ['>=', ['get', 'population'], 1000000], 5, 0],
          6, ['case', ['>=', ['get', 'population'], 500000], 5, 0],
          8, 5
        ],
        'circle-color': 'rgba(255, 100, 120, 0.5)',
        'circle-stroke-width': 0.5,
        'circle-stroke-color': 'rgba(255, 100, 120, 0.3)'
      }
    });

    // City popups
    map.on('click', 'cities-dots', (e) => {
      const props = e.features[0].properties;
      const pop = props.population.toLocaleString();
      new maplibregl.Popup({ closeButton: false, offset: 8 })
        .setLngLat(e.lngLat)
        .setHTML(`<strong>${props.name}, ${props.country}</strong><br>Population: ${pop}`)
        .addTo(map);
    });

    map.on('mouseenter', 'cities-dots', () => { map.getCanvas().style.cursor = 'pointer'; });
    map.on('mouseleave', 'cities-dots', () => { map.getCanvas().style.cursor = ''; });

    map.on('data', (e) => {
      if (e.sourceId && e.sourceId.startsWith('no2-')) {
        updateBufferIndicator();
      }
    });

    goToMonth(0);
  });
}

function pmtilesUrl(index) {
  return `pmtiles://${location.origin}${location.pathname.replace(/\/[^/]*$/, '/')}${TILES_DIR}/no2_${months[index]}.pmtiles`;
}

function formatMonth(monthStr) {
  const [year, month] = monthStr.split('-');
  return `${MONTH_NAMES[parseInt(month, 10) - 1]} ${year}`;
}

function updateMonthLabel() {
  document.getElementById('month-label').textContent = formatMonth(months[currentIndex]);
}

function updateBufferIndicator() {
  if (months.length === 0) return;
  months.forEach((_, i) => {
    const seg = document.getElementById(`buffer-segment-${i}`);
    if (!seg) return;

    let isPrebufferTarget = false;
    for (let p = 0; p <= PREBUFFER_FRAMES; p++) {
      if (i === (currentIndex + p) % months.length) isPrebufferTarget = true;
    }

    let targetClass = 'timeline-buffer-segment';
    if (isPrebufferTarget) {
      const sourceId = `no2-${i}`;
      const isLoaded = map.getSource(sourceId) && map.isSourceLoaded(sourceId);
      if (isLoaded) targetClass = 'timeline-buffer-segment loaded';
    }

    if (seg.className !== targetClass) {
      seg.className = targetClass;
    }
  });
}

function goToMonth(index) {
  if (months.length === 0) return;
  currentIndex = ((index % months.length) + months.length) % months.length;

  months.forEach((_, i) => {
    let isPrebuffer = false;
    for (let p = 1; p <= PREBUFFER_FRAMES; p++) {
      if (i === (currentIndex + p) % months.length) isPrebuffer = true;
    }
    
    // Keep the immediately previous frame visible but transparent for 1 step to prevent flashing
    let isPrevious = i === (currentIndex - 1 + months.length) % months.length;
    
    let targetState = 0; // 0 = none, 1 = prebuffer, 2 = visible
    if (i === currentIndex) {
      targetState = 2;
    } else if (isPrebuffer || isPrevious) {
      targetState = 1;
    }

    if (layerStates[i] !== targetState) {
      if (targetState === 2) {
        if (layerStates[i] !== 1) map.setLayoutProperty(`no2-layer-${i}`, 'visibility', 'visible');
        map.setPaintProperty(`no2-layer-${i}`, 'raster-opacity', 0.6);
      } else if (targetState === 1) {
        if (layerStates[i] !== 2) map.setLayoutProperty(`no2-layer-${i}`, 'visibility', 'visible');
        map.setPaintProperty(`no2-layer-${i}`, 'raster-opacity', 0);
      } else {
        map.setLayoutProperty(`no2-layer-${i}`, 'visibility', 'none');
      }
      layerStates[i] = targetState;
    }
  });

  document.getElementById('timeline').value = currentIndex;
  updateMonthLabel();
  updateBufferIndicator();
}

// --- Playback ---

let waitId = 0;

function advanceFrame() {
  const nextIndex = (currentIndex + 1) % months.length;
  
  if (!map.isSourceLoaded(`no2-${nextIndex}`)) {
    stopInterval();
    document.getElementById('month-label').textContent = 'Loading\u2026';
    const currentWaitId = ++waitId;
    map.once('idle', () => {
      if (playing && currentWaitId === waitId) {
        goToMonth(nextIndex);
        startInterval();
      }
    });
    return;
  }
  
  goToMonth(nextIndex);
}

function startInterval() {
  stopInterval();
  playInterval = setInterval(advanceFrame, PLAY_SPEED_MS);
}

function stopInterval() {
  if (playInterval) clearInterval(playInterval);
  playInterval = null;
}

function togglePlay() {
  if (playing) {
    // Pause
    playing = false;
    waitId++; // invalidate any pending waits
    stopInterval();
    updateMonthLabel(); // ensure loading text is cleared
    document.getElementById('icon-play').style.display = '';
    document.getElementById('icon-pause').style.display = 'none';
    return;
  }

  // Start
  playing = true;
  document.getElementById('icon-play').style.display = 'none';
  document.getElementById('icon-pause').style.display = '';

  if (!map.areTilesLoaded()) {
    document.getElementById('month-label').textContent = 'Loading\u2026';
    const currentWaitId = ++waitId;
    map.once('idle', () => {
      if (playing && currentWaitId === waitId) {
        updateMonthLabel();
        startInterval();
      }
    });
  } else {
    startInterval();
  }
}

// --- Event listeners ---

function manualSeek(index) {
  if (playing) {
    waitId++;
    stopInterval();
    startInterval();
    updateMonthLabel();
  }
  goToMonth(index);
}

document.getElementById('btn-prev').addEventListener('click', () => manualSeek(currentIndex - 1));
document.getElementById('btn-next').addEventListener('click', () => manualSeek(currentIndex + 1));
document.getElementById('btn-play').addEventListener('click', togglePlay);

document.getElementById('speed-select').addEventListener('change', (e) => {
  PLAY_SPEED_MS = parseInt(e.target.value, 10);
  if (playing) {
    waitId++;
    stopInterval();
    startInterval();
  }
});

document.getElementById('timeline').addEventListener('input', (e) => {
  manualSeek(parseInt(e.target.value, 10));
});

// Projection toggle
document.getElementById('btn-flat').addEventListener('click', () => {
  map.setProjection({ type: 'mercator' });
  document.getElementById('btn-flat').classList.add('active');
  document.getElementById('btn-globe').classList.remove('active');
});

document.getElementById('btn-globe').addEventListener('click', () => {
  map.setProjection({ type: 'globe' });
  document.getElementById('btn-globe').classList.add('active');
  document.getElementById('btn-flat').classList.remove('active');
});

// Base map toggle
document.getElementById('btn-dark').addEventListener('click', () => {
  map.setLayoutProperty('carto-dark', 'visibility', 'visible');
  map.setLayoutProperty('esri-satellite', 'visibility', 'none');
  document.getElementById('btn-dark').classList.add('active');
  document.getElementById('btn-satellite').classList.remove('active');
});

document.getElementById('btn-satellite').addEventListener('click', () => {
  map.setLayoutProperty('carto-dark', 'visibility', 'none');
  map.setLayoutProperty('esri-satellite', 'visibility', 'visible');
  document.getElementById('btn-satellite').classList.add('active');
  document.getElementById('btn-dark').classList.remove('active');
});

// Cities toggle
document.getElementById('toggle-cities').addEventListener('change', (e) => {
  const vis = e.target.checked ? 'visible' : 'none';
  map.setLayoutProperty('cities-labels', 'visibility', vis);
  map.setLayoutProperty('cities-dots', 'visibility', vis);
  map.setLayoutProperty('cities-glow', 'visibility', vis);
});

// Sidebar toggle
document.getElementById('sidebar-toggle').addEventListener('click', () => {
  document.getElementById('sidebar').classList.toggle('open');
});

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
  if (e.target.tagName === 'INPUT') return;
  switch (e.key) {
    case ' ':
      e.preventDefault();
      togglePlay();
      break;
    case 'ArrowLeft':
      goToMonth(currentIndex - 1);
      break;
    case 'ArrowRight':
      goToMonth(currentIndex + 1);
      break;
  }
});

init();
