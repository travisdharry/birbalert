let tooltip = null;

function showTooltip(event, text) {
    if (!tooltip) {
        tooltip = d3.select('body')
            .append('div')
            .attr('class', 'tooltip')
            .style('position', 'absolute')
            .style('background', 'rgba(0,0,0,0.8)')
            .style('color', 'white')
            .style('padding', '8px')
            .style('border-radius', '4px')
            .style('pointer-events', 'none');
    }
    
    tooltip
        .style('opacity', 1)
        .html(text)
        .style('left', `${event.pageX + 10}px`)
        .style('top', `${event.pageY - 20}px`);
}

function hideTooltip() {
    if (tooltip) {
        tooltip.style('opacity', 0);
    }
}

export function renderDailyTrendChart(data, containerId) {
    const margin = {top: 20, right: 20, bottom: 50, left: 60};
    const width = 800 - margin.left - margin.right;
    const height = 300 - margin.top - margin.bottom;
    
    d3.select(`#${containerId}`).html('');
    
    const svg = d3.select(`#${containerId}`)
        .append('svg')
        .attr('width', width + margin.left + margin.right)
        .attr('height', height + margin.top + margin.bottom)
        .append('g')
        .attr('transform', `translate(${margin.left},${margin.top})`);
    
    const x = d3.scaleTime()
        .domain(d3.extent(data, d => d.date))
        .range([0, width]);
    
    const y = d3.scaleLinear()
        .domain([0, d3.max(data, d => d.count)])
        .range([height, 0]);
    
    const line = d3.line()
        .x(d => x(d.date))
        .y(d => y(d.count))
        .curve(d3.curveMonotoneX);
    
    // Line
    svg.append('path')
        .datum(data)
        .attr('fill', 'none')
        .attr('stroke', '#253333')
        .attr('stroke-width', 2)
        .attr('d', line);
    
    // Dots
    svg.selectAll('.dot')
        .data(data)
        .enter()
        .append('circle')
        .attr('class', 'dot')
        .attr('cx', d => x(d.date))
        .attr('cy', d => y(d.count))
        .attr('r', 4)
        .attr('fill', '#253333')
        .on('mouseover', function(event, d) {
            showTooltip(event, `${d.date.toLocaleDateString()}: ${d.count} birds`);
        })
        .on('mouseout', hideTooltip);
    
    // Axes
    svg.append('g')
        .attr('transform', `translate(0,${height})`)
        .call(d3.axisBottom(x));
    
    svg.append('g')
        .call(d3.axisLeft(y));
    
    svg.append('text')
        .attr('x', width / 2)
        .attr('y', -10)
        .attr('text-anchor', 'middle')
        .style('font-weight', 'bold')
        .text('Daily Trend');
}

export function renderHourTimelineChart(data, containerId) {
    const margin = {top: 20, right: 20, bottom: 50, left: 60};
    const width = 800 - margin.left - margin.right;
    const height = 280 - margin.top - margin.bottom;
    
    d3.select(`#${containerId}`).html('');
    
    const svg = d3.select(`#${containerId}`)
        .append('svg')
        .attr('width', width + margin.left + margin.right)
        .attr('height', height + margin.top + margin.bottom)
        .append('g')
        .attr('transform', `translate(${margin.left},${margin.top})`);

    const x = d3.scaleLinear()
        .domain([0, 23])
        .range([0, width]);
    
    const y = d3.scaleLinear()
        .domain([0, d3.max(data, d => d.count)]);

    y.range([height, 0]);

    const line = d3.line()
        .x(d => x(d.hour))
        .y(d => y(d.count))
        .curve(d3.curveMonotoneX);

    svg.append('path')
        .datum(data)
        .attr('fill', 'none')
        .attr('stroke', '#253333')
        .attr('stroke-width', 2)
        .attr('d', line);

    svg.selectAll('.dot')
        .data(data)
        .enter()
        .append('circle')
        .attr('class', 'dot')
        .attr('cx', d => x(d.hour))
        .attr('cy', d => y(d.count))
        .attr('r', 3.5)
        .attr('fill', '#253333')
        .on('mouseover', function(event, d) {
            showTooltip(event, `${d.hour}:00 - ${d.count} detections`);
        })
        .on('mouseout', hideTooltip);

    svg.append('g')
        .attr('transform', `translate(0,${height})`)
        .call(d3.axisBottom(x).ticks(12).tickFormat(d => `${d}:00`));

    svg.append('g')
        .call(d3.axisLeft(y));
}
