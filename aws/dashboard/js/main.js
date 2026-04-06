import { api } from './api.js';
import { renderHourTimelineChart, renderDailyTrendChart } from './charts.js';

let currentData = [];

function toLocalDateTimeInputValue(date) {
    const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
    return local.toISOString().slice(0, 16);
}

function buildApiFilters() {
    const startValue = document.getElementById('startDateTime').value;
    const endValue = document.getElementById('endDateTime').value;
    const filters = { limit: 5000 };

    if (startValue) {
        filters.start_date = startValue.split('T')[0];
    }
    if (endValue) {
        filters.end_date = endValue.split('T')[0];
    }

    return filters;
}

function populateSpeciesFilter(data) {
    const speciesFilter = document.getElementById('speciesFilter');
    const selected = new Set(Array.from(speciesFilter.selectedOptions).map(o => o.value));
    const species = [...new Set(data.map(d => d.species))].sort((a, b) => a.localeCompare(b));

    speciesFilter.innerHTML = '';
    species.forEach(name => {
        const option = document.createElement('option');
        option.value = name;
        option.textContent = name;
        option.selected = selected.has(name);
        speciesFilter.appendChild(option);
    });
}

function applyClientFilters(data) {
    const selectedSpecies = Array.from(document.getElementById('speciesFilter').selectedOptions).map(o => o.value);
    const speciesSet = new Set(selectedSpecies);
    const alertMode = document.getElementById('alertMode').value;
    const minConfidence = parseFloat(document.getElementById('minConfidence').value);
    const start = new Date(document.getElementById('startDateTime').value).getTime();
    const end = new Date(document.getElementById('endDateTime').value).getTime();

    return data.filter(d => {
        const tsMs = Number(d.timestamp) * 1000;
        const matchesTime = (!Number.isNaN(start) ? tsMs >= start : true) && (!Number.isNaN(end) ? tsMs <= end : true);
        const matchesSpecies = speciesSet.size > 0 ? speciesSet.has(d.species) : true;
        const matchesAlertMode = alertMode === 'alerted' ? Boolean(d.alerted) : true;
        const matchesConfidence = Number(d.confidence) >= minConfidence;
        return matchesTime && matchesSpecies && matchesAlertMode && matchesConfidence;
    });
}

async function loadData() {
    try {
        showLoading();

        const apiFilters = buildApiFilters();
        const rawData = await api.getDetections(apiFilters);
        populateSpeciesFilter(rawData);
        currentData = applyClientFilters(rawData);

        // Update stats
        updateStats(currentData);

        // Update list and charts
        updateAlertedList(currentData);
        renderHourTimelineChart(api.aggregateByHour(currentData), 'hourTimelineChart');
        renderDailyTrendChart(api.aggregateByDate(currentData), 'dailyTrendChart');

        // Update timestamp
        document.getElementById('lastUpdate').textContent = new Date().toLocaleString();

        hideLoading();
    } catch (error) {
        console.error('Error loading data:', error);
        alert('Failed to load data. Check console for details.');
        hideLoading();
    }
}

function updateStats(data) {
    const total = data.length;
    const species = new Set(data.map(d => d.species)).size;

    document.getElementById('totalDetections').textContent = total;
    document.getElementById('uniqueSpecies').textContent = species;
}

function updateAlertedList(data) {
    const container = document.getElementById('alertedList');
    const alerted = data
        .filter(d => d.alerted)
        .sort((a, b) => Number(b.timestamp) - Number(a.timestamp))
        .slice(0, 10);

    if (alerted.length === 0) {
        container.innerHTML = '<p class="empty-note">No alerted detections in the selected range.</p>';
        return;
    }

    container.innerHTML = alerted.map(d => {
        const time = new Date(Number(d.timestamp) * 1000).toLocaleString();
        const confidence = (Number(d.confidence) * 100).toFixed(1);
        return `
            <article class="alert-item">
                <div>
                    <h3>${d.species}</h3>
                    <p>${time}</p>
                </div>
                <span>${confidence}%</span>
            </article>
        `;
    }).join('');
}

function showLoading() {
    document.body.classList.add('loading');
}

function hideLoading() {
    document.body.classList.remove('loading');
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    // Set default date range (last 24 hours)
    const end = new Date();
    const start = new Date();
    start.setHours(start.getHours() - 24);

    document.getElementById('startDateTime').value = toLocalDateTimeInputValue(start);
    document.getElementById('endDateTime').value = toLocalDateTimeInputValue(end);

    const minConfidence = document.getElementById('minConfidence');
    const minConfidenceValue = document.getElementById('minConfidenceValue');
    minConfidenceValue.textContent = Number(minConfidence.value).toFixed(2);

    // Load initial data
    loadData();

    // Refresh button
    document.getElementById('refreshBtn').addEventListener('click', loadData);
    document.getElementById('speciesFilter').addEventListener('change', loadData);
    document.getElementById('startDateTime').addEventListener('change', loadData);
    document.getElementById('endDateTime').addEventListener('change', loadData);
    document.getElementById('alertMode').addEventListener('change', loadData);
    minConfidence.addEventListener('input', () => {
        minConfidenceValue.textContent = Number(minConfidence.value).toFixed(2);
    });
    minConfidence.addEventListener('change', loadData);

    // Auto-refresh every 5 minutes
    setInterval(loadData, 5 * 60 * 1000);
});
