// vision/motion.js
// ----------------------------------------------------------------------------
// Motion detection by frame differencing — catches a fast/blurred ball that a
// color or object model misses, by finding where luminance changed between two
// frames. Pure over {data,width,height} images, so it unit-tests in node.
// ----------------------------------------------------------------------------

function luma(d, i) { return 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]; }

/**
 * Centroid + bbox of the region that changed between prev and cur frames.
 * @param {{data,width,height}} prev
 * @param {{data,width,height}} cur
 * @param {{threshold?:number, step?:number}} opts  luminance-delta threshold (0-255)
 */
export function motionCentroid(prev, cur, opts = {}) {
  const { threshold = 28, step = 2 } = opts;
  const { data: a, width, height } = prev;
  const { data: b } = cur;
  let sx = 0, sy = 0, n = 0;
  let minX = width, minY = height, maxX = 0, maxY = 0;
  for (let y = 0; y < height; y += step) {
    for (let x = 0; x < width; x += step) {
      const i = (y * width + x) * 4;
      if (Math.abs(luma(b, i) - luma(a, i)) > threshold) {
        sx += x; sy += y; n++;
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
      }
    }
  }
  const sampled = Math.ceil(width / step) * Math.ceil(height / step);
  if (n === 0) return { found: false, x: 0, y: 0, area: 0, count: 0, bbox: null };
  return {
    found: true,
    x: (sx / n) / width,
    y: (sy / n) / height,
    area: n / sampled,
    count: n,
    bbox: { x: minX / width, y: minY / height, w: (maxX - minX) / width, h: (maxY - minY) / height },
  };
}

export default { motionCentroid };
