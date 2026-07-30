// Plain JSON symbol objects — @arcgis/core accepts these without importing the ES module symbol classes.

export function dotSymbol(color: string) {
  return {
    type: 'simple-marker' as const,
    style: 'circle' as const,
    color,
    size: 14,
    outline: { color: 'white', width: 2 },
  };
}

export function lineSymbolFor(color: string, opts?: { dashed?: boolean }) {
  return {
    type: 'simple-line' as const,
    color,
    width: 4,
    style: opts?.dashed ? ('dash' as const) : ('solid' as const),
  };
}

export function fillSymbolFor(color: string, opts?: { dashed?: boolean }) {
  return {
    type: 'simple-fill' as const,
    color: [...hexToRgb(color), 0.3],
    outline: {
      color,
      width: 2,
      style: opts?.dashed ? ('dash' as const) : ('solid' as const),
    },
  };
}

function hexToRgb(hex: string): [number, number, number] {
  const clean = hex.replace('#', '');
  const r = parseInt(clean.substring(0, 2), 16);
  const g = parseInt(clean.substring(2, 4), 16);
  const b = parseInt(clean.substring(4, 6), 16);
  return [r, g, b];
}
