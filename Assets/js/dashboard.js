/* ═══════════════════════════════════════════════════════════════
   Developer Health Analyzer — Dashboard JavaScript
   Version 1.0.0 | MIT License
   ═══════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  // ── Load Report Data ──────────────────────────────────────
  const dataElement = document.getElementById('report-data');
  const report = dataElement ? JSON.parse(dataElement.textContent) : {};
  const scores = (report || {}).Scores || {};

  // ── Utility Helpers ───────────────────────────────────────
  function bytesToGb(value) {
    return Math.round((Number(value || 0) / 1073741824) * 100) / 100;
  }

  function getScoreClass(score) {
    if (score >= 85) return 'excellent';
    if (score >= 70) return 'good';
    if (score >= 55) return 'warn';
    return 'bad';
  }

  function getScoreColor(score) {
    const style = getComputedStyle(document.documentElement);
    if (score >= 85) return style.getPropertyValue('--excellent').trim() || '#22c55e';
    if (score >= 70) return style.getPropertyValue('--good').trim()      || '#3b82f6';
    if (score >= 55) return style.getPropertyValue('--fair').trim()      || '#f59e0b';
    return style.getPropertyValue('--critical').trim() || '#ef4444';
  }

  function isDark() {
    return document.documentElement.dataset.bsTheme !== 'light';
  }

  function chartTextColor() {
    return isDark() ? '#94a3b8' : '#475569';
  }

  function chartGridColor() {
    return isDark() ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)';
  }

  // ── Chart.js Global Defaults ──────────────────────────────
  if (window.Chart) {
    Chart.defaults.color = chartTextColor();
    Chart.defaults.borderColor = chartGridColor();
    Chart.defaults.font.family = "'Segoe UI Variable', 'Segoe UI', system-ui, sans-serif";
    Chart.defaults.font.size = 12;
    Chart.defaults.plugins.legend.labels.usePointStyle = true;
    Chart.defaults.plugins.legend.labels.padding = 16;
    Chart.defaults.plugins.tooltip.cornerRadius = 6;
    Chart.defaults.plugins.tooltip.padding = 10;
  }

  // ── Chart Factory ─────────────────────────────────────────
  const charts = [];
  function makeChart(id, config) {
    const canvas = document.getElementById(id);
    if (!canvas || !window.Chart) return null;
    const chart = new Chart(canvas, config);
    charts.push(chart);
    return chart;
  }

  // ── Score Counter Animation ───────────────────────────────
  function animateCounters() {
    document.querySelectorAll('.score-value').forEach(el => {
      const text = el.textContent;
      const match = text.match(/^(\d+)/);
      if (!match) return;
      const target = parseInt(match[1], 10);
      const suffix = text.replace(/^\d+/, '');
      let current = 0;
      const duration = 1200;
      const start = performance.now();

      function step(now) {
        const elapsed = now - start;
        const progress = Math.min(elapsed / duration, 1);
        const eased = 1 - Math.pow(1 - progress, 3);
        current = Math.round(eased * target);
        el.childNodes[0].textContent = current;
        if (progress < 1) requestAnimationFrame(step);
      }

      // Wrap text node for animation
      if (el.childNodes[0] && el.childNodes[0].nodeType === 3) {
        el.childNodes[0].textContent = '0';
      }
      requestAnimationFrame(step);
    });
  }

  // ── 1. Disk Usage Doughnut Chart ──────────────────────────
  const drives = ((report.Storage || {}).Drives || []);
  if (drives.length > 0) {
    const driveColors = ['#3b82f6', '#22c55e', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4', '#ec4899'];
    makeChart('storageChart', {
      type: 'doughnut',
      data: {
        labels: drives.map(d => d.Drive + ' ' + (d.Label || '')),
        datasets: [{
          data: drives.map(d => bytesToGb(d.UsedBytes)),
          backgroundColor: driveColors.slice(0, drives.length),
          borderWidth: 0,
          hoverOffset: 8
        }]
      },
      options: {
        cutout: '65%',
        plugins: {
          legend: { position: 'bottom' },
          title: { display: true, text: 'Disk Usage by Drive (GB)', font: { size: 14, weight: 600 } },
          tooltip: {
            callbacks: {
              label: ctx => {
                const drive = drives[ctx.dataIndex];
                return `${ctx.label}: ${ctx.parsed} GB used / ${bytesToGb(drive.TotalBytes)} GB total`;
              }
            }
          }
        }
      }
    });
  }

  // ── 2. Top Memory Processes Bar Chart ─────────────────────
  const topMem = ((report.Performance || {}).TopMemoryProcesses || []).slice(0, 10);
  if (topMem.length > 0) {
    makeChart('processChart', {
      type: 'bar',
      data: {
        labels: topMem.map(p => p.Name),
        datasets: [{
          label: 'Memory (MB)',
          data: topMem.map(p => p.MemoryMB),
          backgroundColor: topMem.map((_, i) => {
            const alpha = 1 - (i * 0.06);
            return `rgba(59, 130, 246, ${alpha})`;
          }),
          borderRadius: 4,
          borderSkipped: false
        }]
      },
      options: {
        indexAxis: 'y',
        plugins: {
          legend: { display: false },
          title: { display: true, text: 'Top Memory Processes', font: { size: 14, weight: 600 } }
        },
        scales: {
          x: { grid: { color: chartGridColor() }, ticks: { color: chartTextColor() } },
          y: { grid: { display: false }, ticks: { color: chartTextColor(), font: { size: 11 } } }
        }
      }
    });
  }

  // ── 3. Event Timeline Chart ───────────────────────────────
  const timeline = ((report.EventLogs || {}).EventTimeline || []);
  if (timeline.length > 0) {
    makeChart('eventChart', {
      type: 'line',
      data: {
        labels: timeline.map(e => e.Date),
        datasets: [{
          label: 'Events',
          data: timeline.map(e => e.Count),
          borderColor: '#f59e0b',
          backgroundColor: 'rgba(245, 158, 11, 0.1)',
          borderWidth: 2,
          tension: 0.4,
          fill: true,
          pointRadius: 3,
          pointBackgroundColor: '#f59e0b',
          pointHoverRadius: 6
        }]
      },
      options: {
        plugins: {
          title: { display: true, text: 'Event Log Timeline', font: { size: 14, weight: 600 } },
          legend: { display: false }
        },
        scales: {
          x: { grid: { color: chartGridColor() }, ticks: { color: chartTextColor(), maxRotation: 45 } },
          y: { grid: { color: chartGridColor() }, ticks: { color: chartTextColor() }, beginAtZero: true }
        }
      }
    });
  }

  // ── 4. Security Radar Chart ───────────────────────────────
  const security = report.Security || {};
  const securityChecks = [
    { label: 'Firewall',  score: (security.Firewall || []).every(f => f.Enabled) ? 100 : 30 },
    { label: 'Defender',  score: (security.Defender && security.Defender.RealTimeProtectionEnabled) ? 100 : 20 },
    { label: 'UAC',       score: (security.UAC && security.UAC.Enabled) ? 100 : 20 },
    { label: 'Secure Boot', score: security.SecureBoot === true ? 100 : (security.SecureBoot === false ? 20 : 50) },
    { label: 'BitLocker', score: (security.BitLocker || []).some(b => b.ProtectionStatus === 1) ? 100 : 30 },
    { label: 'Memory Integrity', score: (security.CoreIsolation && security.CoreIsolation.MemoryIntegrity === 1) ? 100 : 40 }
  ];
  const secRadarCanvas = document.getElementById('securityRadar');
  if (secRadarCanvas && window.Chart) {
    makeChart('securityRadar', {
      type: 'radar',
      data: {
        labels: securityChecks.map(c => c.label),
        datasets: [{
          label: 'Security',
          data: securityChecks.map(c => c.score),
          backgroundColor: 'rgba(59, 130, 246, 0.15)',
          borderColor: '#3b82f6',
          borderWidth: 2,
          pointBackgroundColor: securityChecks.map(c => getScoreColor(c.score)),
          pointRadius: 5
        }]
      },
      options: {
        scales: {
          r: {
            beginAtZero: true,
            max: 100,
            ticks: { stepSize: 25, color: chartTextColor(), backdropColor: 'transparent' },
            grid: { color: chartGridColor() },
            pointLabels: { color: chartTextColor(), font: { size: 12 } },
            angleLines: { color: chartGridColor() }
          }
        },
        plugins: {
          title: { display: true, text: 'Security Posture', font: { size: 14, weight: 600 } },
          legend: { display: false }
        }
      }
    });
  }

  // ── 5. Developer Folders Bar Chart ────────────────────────
  const devFolders = ((report.DeveloperEnvironment || {}).Folders || [])
    .filter(f => f.Exists && f.SizeGB > 0)
    .sort((a, b) => b.SizeGB - a.SizeGB)
    .slice(0, 15);
  const devBarCanvas = document.getElementById('devFoldersChart');
  if (devBarCanvas && devFolders.length > 0) {
    makeChart('devFoldersChart', {
      type: 'bar',
      data: {
        labels: devFolders.map(f => f.Name),
        datasets: [{
          label: 'Size (GB)',
          data: devFolders.map(f => f.SizeGB),
          backgroundColor: devFolders.map((_, i) => {
            const hue = 220 + (i * 12);
            return `hsl(${hue}, 70%, 55%)`;
          }),
          borderRadius: 4,
          borderSkipped: false
        }]
      },
      options: {
        indexAxis: 'y',
        plugins: {
          legend: { display: false },
          title: { display: true, text: 'Developer Folder Sizes', font: { size: 14, weight: 600 } }
        },
        scales: {
          x: { grid: { color: chartGridColor() }, ticks: { color: chartTextColor() } },
          y: { grid: { display: false }, ticks: { color: chartTextColor(), font: { size: 11 } } }
        }
      }
    });
  }

  // ── 6. Battery Health Gauge ───────────────────────────────
  const battery = report.Battery || {};
  const batCanvas = document.getElementById('batteryChart');
  if (batCanvas && battery.Present && (battery.Batteries || []).length > 0) {
    const bat = battery.Batteries[0];
    const healthPct = bat.EstimatedHealthPercent || 0;
    makeChart('batteryChart', {
      type: 'doughnut',
      data: {
        labels: ['Health', 'Wear'],
        datasets: [{
          data: [healthPct, 100 - healthPct],
          backgroundColor: [getScoreColor(healthPct), isDark() ? '#1e293b' : '#e2e8f0'],
          borderWidth: 0
        }]
      },
      options: {
        cutout: '75%',
        plugins: {
          title: { display: true, text: `Battery Health: ${healthPct}%`, font: { size: 14, weight: 600 } },
          legend: { display: false }
        }
      }
    });
  }

  // ── 7. Folder Treemap ─────────────────────────────────────
  const treemap = document.getElementById('folderTreemap');
  const treemapData = ((report.Storage || {}).Treemap || []).slice(0, 40);
  if (treemap && treemapData.length > 0) {
    const maxSize = Math.max(...treemapData.map(f => Number(f.SizeBytes || 1)), 1);
    const colors = ['#1d4ed8','#2563eb','#3b82f6','#60a5fa','#7c3aed','#8b5cf6','#06b6d4','#0891b2'];
    treemap.innerHTML = treemapData.map((f, i) => {
      const ratio = Number(f.SizeBytes || 0) / maxSize;
      const basis = Math.max(100, Math.round(ratio * 400));
      const height = Math.max(48, Math.round(ratio * 120));
      const name = String(f.Path || '').split(/[\\/]/).pop() || f.Path;
      const color = colors[i % colors.length];
      return `<div class="treemap-cell" style="flex-basis:${basis}px;height:${height}px;background:linear-gradient(135deg,${color},${color}dd)" title="${f.Path}">
        <strong>${name}</strong><br>${f.SizeGB} GB
      </div>`;
    }).join('');
  } else if (treemap) {
    treemap.innerHTML = '<span class="muted">No folder treemap data available.</span>';
  }

  // ── Sortable Tables ───────────────────────────────────────
  document.querySelectorAll('table.sortable th').forEach(header => {
    header.addEventListener('click', () => {
      const table = header.closest('table');
      const tbody = table.querySelector('tbody');
      const rows = Array.from(tbody.querySelectorAll('tr'));
      const colIdx = Array.from(header.parentElement.children).indexOf(header);
      const asc = header.dataset.sort !== 'asc';

      // Reset all headers in this table
      header.parentElement.querySelectorAll('th').forEach(th => delete th.dataset.sort);
      header.dataset.sort = asc ? 'asc' : 'desc';

      rows.sort((a, b) => {
        const av = (a.children[colIdx] || {}).innerText || '';
        const bv = (b.children[colIdx] || {}).innerText || '';
        const an = parseFloat(av.replace(/[^0-9.\-]/g, ''));
        const bn = parseFloat(bv.replace(/[^0-9.\-]/g, ''));
        const result = (!isNaN(an) && !isNaN(bn)) ? an - bn : av.localeCompare(bv, undefined, { numeric: true });
        return asc ? result : -result;
      });

      rows.forEach(row => tbody.appendChild(row));
    });
  });

  // ── Table Search ──────────────────────────────────────────
  document.querySelectorAll('.table-search').forEach(input => {
    input.addEventListener('input', () => {
      const table = document.getElementById(input.dataset.table);
      if (!table) return;
      const query = input.value.toLowerCase();
      table.querySelectorAll('tbody tr').forEach(row => {
        row.style.display = row.innerText.toLowerCase().includes(query) ? '' : 'none';
      });
    });
  });

  // ── CSV Export ─────────────────────────────────────────────
  document.querySelectorAll('.export-csv').forEach(btn => {
    btn.addEventListener('click', () => {
      const tableId = btn.dataset.table;
      const table = document.getElementById(tableId);
      if (!table) return;

      const rows = [];
      // Header row
      const headers = Array.from(table.querySelectorAll('thead th')).map(th => `"${th.innerText.replace(/[↕↑↓]/g, '').trim()}"`);
      rows.push(headers.join(','));
      // Data rows
      table.querySelectorAll('tbody tr').forEach(tr => {
        if (tr.style.display === 'none') return;
        const cells = Array.from(tr.querySelectorAll('td')).map(td => `"${td.innerText.replace(/"/g, '""')}"`);
        rows.push(cells.join(','));
      });

      const blob = new Blob([rows.join('\n')], { type: 'text/csv;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${tableId}_export.csv`;
      a.click();
      URL.revokeObjectURL(url);
    });
  });

  // ── Theme Toggle ──────────────────────────────────────────
  const themeToggle = document.getElementById('themeToggle');
  const savedTheme = localStorage.getItem('dha-theme');
  if (savedTheme) {
    document.documentElement.dataset.bsTheme = savedTheme;
  }

  if (themeToggle) {
    themeToggle.addEventListener('click', () => {
      const html = document.documentElement;
      const newTheme = html.dataset.bsTheme === 'dark' ? 'light' : 'dark';
      html.dataset.bsTheme = newTheme;
      localStorage.setItem('dha-theme', newTheme);

      // Update Chart.js colors on theme change
      const textColor = chartTextColor();
      const gridColor = chartGridColor();
      Chart.defaults.color = textColor;
      Chart.defaults.borderColor = gridColor;

      charts.forEach(chart => {
        if (chart.options.scales) {
          Object.values(chart.options.scales).forEach(scale => {
            if (scale.grid) scale.grid.color = gridColor;
            if (scale.ticks) scale.ticks.color = textColor;
            if (scale.pointLabels) scale.pointLabels.color = textColor;
            if (scale.angleLines) scale.angleLines.color = gridColor;
          });
        }
        chart.update('none');
      });
    });
  }

  // ── Print Button ──────────────────────────────────────────
  const printBtn = document.getElementById('printReport');
  if (printBtn) {
    printBtn.addEventListener('click', () => window.print());
  }

  // ── Smooth Scroll for Section Links ───────────────────────
  document.querySelectorAll('a[href^="#"]').forEach(link => {
    link.addEventListener('click', e => {
      e.preventDefault();
      const target = document.querySelector(link.getAttribute('href'));
      if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });

  // ── 8. Storage Category Doughnut Chart (C6) ───────────────
  const diskCategories = ((report.Storage || {}).DiskUsageSummary || []).filter(c => c.SizeGB > 0);
  if (document.getElementById('storageCategoryChart') && diskCategories.length > 0) {
    const catColors = ['#8b5cf6', '#ec4899', '#f59e0b', '#10b981', '#3b82f6', '#06b6d4'];
    makeChart('storageCategoryChart', {
      type: 'doughnut',
      data: {
        labels: diskCategories.map(c => c.Category),
        datasets: [{
          data: diskCategories.map(c => c.SizeGB),
          backgroundColor: catColors.slice(0, diskCategories.length),
          borderWidth: 0
        }]
      },
      options: {
        plugins: { title: { display: true, text: 'Storage by Category (GB)', font: { size: 14, weight: 600 } }, legend: { position: 'bottom' } }
      }
    });
  }

  // ── 9. Disk I/O Bar Chart (C2) ────────────────────────────
  const diskIo = ((report.Performance || {}).DiskActivity || []);
  if (document.getElementById('diskIoChart') && diskIo.length > 0) {
    makeChart('diskIoChart', {
      type: 'bar',
      data: {
        labels: diskIo.map(d => d.Disk),
        datasets: [
          { label: 'Read (B/s)', data: diskIo.map(d => d.ReadBytesPerSec), backgroundColor: '#3b82f6', borderRadius: 4 },
          { label: 'Write (B/s)', data: diskIo.map(d => d.WriteBytesPerSec), backgroundColor: '#f59e0b', borderRadius: 4 }
        ]
      },
      options: {
        plugins: { title: { display: true, text: 'Disk I/O Activity', font: { size: 14, weight: 600 } } },
        scales: {
          x: { grid: { color: chartGridColor() }, ticks: { color: chartTextColor() } },
          y: { grid: { color: chartGridColor() }, ticks: { color: chartTextColor() } }
        }
      }
    });
  }

  // ── 10. Boot Time Trend Chart (H5) ────────────────────────
  const bootEvents = ((report.Startup || {}).BootEvents || []);
  if (document.getElementById('bootTimeChart') && bootEvents.length > 0) {
    makeChart('bootTimeChart', {
      type: 'line',
      data: {
        labels: bootEvents.map(e => new Date(e.TimeCreated).toLocaleDateString()),
        datasets: [{
          label: 'Boot Duration (s)',
          data: bootEvents.map(e => e.BootDurationSeconds),
          borderColor: '#10b981',
          backgroundColor: 'rgba(16, 185, 129, 0.1)',
          fill: true,
          tension: 0.3
        }]
      },
      options: {
        plugins: { title: { display: true, text: 'Boot Time Trend', font: { size: 14, weight: 600 } } },
        scales: {
          x: { grid: { color: chartGridColor() }, ticks: { color: chartTextColor() } },
          y: { grid: { color: chartGridColor() }, ticks: { color: chartTextColor() } }
        }
      }
    });
  }

  // ── 11. Charging History Chart (M5) ───────────────────────
  const chargeHistory = ((report.Battery || {}).ChargingHistory || []);
  if (document.getElementById('chargingHistoryChart') && chargeHistory.length > 0) {
    makeChart('chargingHistoryChart', {
      type: 'line',
      data: {
        labels: chargeHistory.map(h => new Date(h.Timestamp).toLocaleDateString()),
        datasets: [{
          label: 'Full Charge Capacity (mWh)',
          data: chargeHistory.map(h => h.FullChargeCapacity),
          borderColor: '#8b5cf6',
          backgroundColor: 'rgba(139, 92, 246, 0.1)',
          fill: true,
          tension: 0.2
        }]
      },
      options: {
        plugins: { title: { display: true, text: 'Battery Capacity History', font: { size: 14, weight: 600 } } },
        scales: {
          x: { grid: { color: chartGridColor() }, ticks: { color: chartTextColor() } },
          y: { grid: { color: chartGridColor() }, ticks: { color: chartTextColor() } }
        }
      }
    });
  }

  // ── 12. Cleanup Categories Chart (H7) ─────────────────────
  const cleanupFindings = ((report.CleanupAdvisor || {}).Findings || []);
  if (document.getElementById('cleanupCategoryChart') && cleanupFindings.length > 0) {
    const cleanupGroups = {};
    cleanupFindings.forEach(f => {
      cleanupGroups[f.Category] = (cleanupGroups[f.Category] || 0) + (f.SizeGB || 0);
    });
    makeChart('cleanupCategoryChart', {
      type: 'bar',
      data: {
        labels: Object.keys(cleanupGroups),
        datasets: [{
          label: 'Size (GB)',
          data: Object.values(cleanupGroups),
          backgroundColor: '#ef4444',
          borderRadius: 4
        }]
      },
      options: {
        indexAxis: 'y',
        plugins: { legend: { display: false }, title: { display: true, text: 'Cleanup Recommendations by Category', font: { size: 14, weight: 600 } } },
        scales: {
          x: { grid: { color: chartGridColor() }, ticks: { color: chartTextColor() } },
          y: { grid: { display: false }, ticks: { color: chartTextColor() } }
        }
      }
    });
  }

  // ── Color-Coded Drive Bars (L6) ───────────────────────────
  const drivesTable = document.getElementById('drivesTable');
  if (drivesTable) {
    drivesTable.querySelectorAll('tbody tr').forEach(tr => {
      Array.from(tr.children).forEach(cell => {
        if (cell.textContent.includes('%')) {
          const pctMatch = cell.textContent.match(/([\d.]+)\s*%/);
          if (pctMatch) {
            const pct = parseFloat(pctMatch[1]);
            let color = 'var(--critical)';
            if (pct >= 30) color = 'var(--excellent)';
            else if (pct >= 15) color = 'var(--fair)';
            if (!cell.querySelector('.drive-usage-bar')) {
              cell.innerHTML = `<div>${cell.textContent}</div><div class="drive-usage-bar"><div style="width: ${pct}%; background: ${color};"></div></div>`;
            }
          }
        }
      });
    });
  }

  // ── Table Row Counts (L5) ─────────────────────────────────
  window.addEventListener('load', () => {
    document.querySelectorAll('.table-count').forEach(el => {
      const container = el.closest('.dashboard-section') || el.closest('div');
      const table = container.querySelector('table tbody');
      if (table) {
        const count = Array.from(table.querySelectorAll('tr')).filter(tr => tr.style.display !== 'none').length;
        el.textContent = count;
      }
    });
  });

  // ── Expand All / Collapse All (L7) ────────────────────────
  const toggleBtn = document.getElementById('toggleAllSections');
  if (toggleBtn) {
    let allExpanded = true;
    toggleBtn.addEventListener('click', () => {
      allExpanded = !allExpanded;
      document.querySelectorAll('.dashboard-section .collapse').forEach(el => {
        if (allExpanded) el.classList.add('show');
        else el.classList.remove('show');
      });
      document.querySelectorAll('.section-toggle').forEach(btn => {
        btn.setAttribute('aria-expanded', allExpanded.toString());
      });
    });
  }

  // ── Initialize Lucide Icons ───────────────────────────────
  if (window.lucide) {
    window.lucide.createIcons();
  }

  // ── Sidebar TOC (H6) ──────────────────────────────────────
  const sections = document.querySelectorAll('.dashboard-section');
  if (sections.length > 0) {
    const nav = document.createElement('nav');
    nav.className = 'sidebar-toc';
    nav.innerHTML = '<strong>Sections</strong>';
    sections.forEach(sec => {
      const title = sec.querySelector('.section-title');
      const id = sec.querySelector('.collapse')?.id;
      if (title && id) {
        const link = document.createElement('a');
        link.href = '#' + id;
        link.textContent = title.textContent.trim();
        link.addEventListener('click', e => {
          e.preventDefault();
          sec.scrollIntoView({ behavior: 'smooth', block: 'start' });
        });
        nav.appendChild(link);
      }
    });
    document.body.appendChild(nav);
  }

  // ── Run Score Animations on Load ──────────────────────────
  if (document.readyState === 'complete') {
    animateCounters();
  } else {
    window.addEventListener('load', animateCounters);
  }

})();
