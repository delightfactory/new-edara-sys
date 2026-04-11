/**
 * Utility for exporting data arrays to a CSV file.
 */
export function downloadAsCSV<T extends Record<string, any>>(
  data: T[],
  filename: string,
  headers?: { key: keyof T; label: string }[]
) {
  if (!data || data.length === 0) return

  // Determine headers if not explicitly provided
  const keys = headers ? headers.map(h => h.key) : Object.keys(data[0]) as Array<keyof T>
  const labels = headers ? headers.map(h => h.label) : keys

  // Build CSV content
  const csvRows: string[] = []
  
  // 1. Add BOM (Byte Order Mark) to ensure Excel opens Arabic characters correctly (UTF-8 with BOM)
  const BOM = '\uFEFF'
  
  // 2. Add header row
  csvRows.push(labels.map(label => escapeCSVCell(String(label))).join(','))

  // 3. Add data rows
  for (const row of data) {
    const values = keys.map(key => {
      const value = row[key]
      if (value === null || value === undefined) return ''
      return escapeCSVCell(String(value))
    })
    csvRows.push(values.join(','))
  }

  // Generate and download
  const csvString = BOM + csvRows.join('\n')
  const blob = new Blob([csvString], { type: 'text/csv;charset=utf-8;' })
  const link = document.createElement('a')
  
  const nav = navigator as any
  if (nav.msSaveBlob) { // IE 10+
    nav.msSaveBlob(blob, filename)
  } else {
    const url = URL.createObjectURL(blob)
    link.setAttribute('href', url)
    link.setAttribute('download', filename.endsWith('.csv') ? filename : `${filename}.csv`)
    link.style.visibility = 'hidden'
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    URL.revokeObjectURL(url)
  }
}

function escapeCSVCell(cell: string): string {
  // If the cell contains comma, newline, or quotes, it must be wrapped in quotes
  // Existing quotes inside the cell must be doubled
  if (cell.includes(',') || cell.includes('\n') || cell.includes('"')) {
    return `"${cell.replace(/"/g, '""')}"`
  }
  return cell
}
