const API_BASE = 'https://83x49whshc.execute-api.us-east-2.amazonaws.com/prod';

class BirdDataAPI {
    async getDetections(filters = {}) {
        const params = new URLSearchParams(filters);
        const response = await fetch(`${API_BASE}/detections?${params}`);
        
        if (!response.ok) {
            throw new Error(`API error: ${response.status}`);
        }
        
        const data = await response.json();
        return data.detections;
    }
    
    async getDateRange() {
        const detections = await this.getDetections({ limit: 10000 });
        const dates = detections.map(d => new Date(d.timestamp * 1000));
        return {
            min: new Date(Math.min(...dates)),
            max: new Date(Math.max(...dates))
        };
    }
    
    // Aggregate by species
    aggregateBySpecies(detections) {
        const counts = {};
        detections.forEach(d => {
            counts[d.species] = (counts[d.species] || 0) + 1;
        });
        return Object.entries(counts)
            .map(([species, count]) => ({ species, count }))
            .sort((a, b) => b.count - a.count);
    }
    
    // Aggregate by hour of day
    aggregateByHour(detections) {
        const hours = Array(24).fill(0);
        detections.forEach(d => {
            hours[d.hour]++;
        });
        return hours.map((count, hour) => ({ hour, count }));
    }
    
    // Aggregate by date
    aggregateByDate(detections) {
        const dates = {};
        detections.forEach(d => {
            dates[d.date] = (dates[d.date] || 0) + 1;
        });
        return Object.entries(dates)
            .map(([date, count]) => ({ date: new Date(date), count }))
            .sort((a, b) => a.date - b.date);
    }
}

export const api = new BirdDataAPI();
