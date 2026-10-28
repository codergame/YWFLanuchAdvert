function insets(value, scale) {
  const source = value || {};
  return {
    top: (Number(source.top) || 0) * scale,
    left: (Number(source.left) || 0) * scale,
    bottom: (Number(source.bottom) || 0) * scale,
    right: (Number(source.right) || 0) * scale
  };
}

function axis(mode, value, parent, screen, scale, intrinsic) {
  if (mode === "fixed") return (Number(value) || 0) * scale;
  if (mode === "percent") return parent * (Number(value) || 0) / 100;
  if (mode === "fullscreen") return screen;
  if (mode === "wrap") return intrinsic;
  return parent;
}

function intrinsicSize(node, proposed, scale, screen) {
  if (node.type === "image") return { width: 120 * scale, height: 80 * scale };
  if (node.type === "button") {
    const font = Math.max(1, (Number(node.fontSize) || 16) * scale);
    const text = node.text || "";
    return { width: text.length * font * 0.6 + 24 * scale, height: font + 16 * scale };
  }
  if (node.type === "container") return measureContainer(node, proposed, scale, screen);
  return { width: 0, height: 0 };
}

function resolveSize(node, parent, scale, screen) {
  const needs = node.size.widthMode === "wrap" || node.size.heightMode === "wrap";
  const intrinsic = needs ? intrinsicSize(node, parent, scale, screen) : { width: 0, height: 0 };
  return {
    width: Math.max(0, axis(node.size.widthMode, node.size.width, parent.width, screen.width, scale, intrinsic.width)),
    height: Math.max(0, axis(node.size.heightMode, node.size.height, parent.height, screen.height, scale, intrinsic.height))
  };
}

function measureContainer(node, proposed, scale, screen) {
  const pad = insets(node.padding, scale);
  const inner = {
    width: Math.max(0, proposed.width - pad.left - pad.right),
    height: Math.max(0, proposed.height - pad.top - pad.bottom)
  };
  const children = node.children || [];
  if ((node.layout || "absolute") === "linear") {
    const vertical = (node.direction || "vertical") !== "horizontal";
    const spacing = (Number(node.spacing) || 0) * scale;
    let main = 0;
    let cross = 0;
    children.forEach((child, index) => {
      const margin = insets(child.margin, scale);
      const size = resolveSize(child, {
        width: Math.max(0, inner.width - margin.left - margin.right),
        height: Math.max(0, inner.height - margin.top - margin.bottom)
      }, scale, screen);
      if (vertical) {
        main += margin.top + size.height + margin.bottom;
        cross = Math.max(cross, margin.left + size.width + margin.right);
      } else {
        main += margin.left + size.width + margin.right;
        cross = Math.max(cross, margin.top + size.height + margin.bottom);
      }
      if (index < children.length - 1) main += spacing;
    });
    return vertical
      ? { width: cross + pad.left + pad.right, height: main + pad.top + pad.bottom }
      : { width: main + pad.left + pad.right, height: cross + pad.top + pad.bottom };
  }
  let maxX = 0;
  let maxY = 0;
  for (const child of children) {
    const margin = insets(child.margin, scale);
    const size = resolveSize(child, inner, scale, screen);
    maxX = Math.max(maxX, (Number(child.x) || 0) * scale + margin.left + size.width + margin.right);
    maxY = Math.max(maxY, (Number(child.y) || 0) * scale + margin.top + size.height + margin.bottom);
  }
  return { width: maxX + pad.left + pad.right, height: maxY + pad.top + pad.bottom };
}

function layoutAbsolute(children, content, scale, screen, frames) {
  for (const child of children) {
    const margin = insets(child.margin, scale);
    const size = resolveSize(child, { width: content.w, height: content.h }, scale, screen);
    frames[child.id] = {
      x: content.x + (Number(child.x) || 0) * scale + margin.left,
      y: content.y + (Number(child.y) || 0) * scale + margin.top,
      w: size.width,
      h: size.height
    };
  }
}

function layoutLinear(node, children, content, scale, screen, frames) {
  const vertical = (node.direction || "vertical") !== "horizontal";
  const spacing = (Number(node.spacing) || 0) * scale;
  const sizes = [];
  const margins = [];
  const weights = [];
  for (const child of children) {
    const margin = insets(child.margin, scale);
    margins.push(margin);
    let size = resolveSize(child, {
      width: Math.max(0, content.w - margin.left - margin.right),
      height: Math.max(0, content.h - margin.top - margin.bottom)
    }, scale, screen);
    const weight = Number(child.weight) || 0;
    if (weight > 0) {
      const mode = vertical ? child.size.heightMode : child.size.widthMode;
      if (mode === "match") {
        if (vertical) size = { ...size, height: 0 };
        else size = { ...size, width: 0 };
      }
    }
    sizes.push(size);
    weights.push(weight);
  }
  const main = (size) => (vertical ? size.height : size.width);
  const gapCount = Math.max(0, children.length - 1);
  const marginMain = margins.reduce((sum, margin) => sum + (vertical ? margin.top + margin.bottom : margin.left + margin.right), 0);
  const base = sizes.reduce((sum, size) => sum + main(size), 0) + spacing * gapCount + marginMain;
  const available = vertical ? content.h : content.w;
  const extra = Math.max(0, available - base);
  const weightSum = weights.reduce((sum, weight) => sum + weight, 0);
  if (weightSum > 0 && extra > 0) {
    sizes.forEach((size, index) => {
      if (weights[index] <= 0) return;
      const add = extra * weights[index] / weightSum;
      if (vertical) size.height += add;
      else size.width += add;
    });
  }
  const gravity = node.gravity || "start";
  let between = spacing;
  let used = sizes.reduce((sum, size) => sum + main(size), 0) + marginMain;
  if (gravity === "spaceBetween" && children.length > 1 && weightSum === 0) {
    between = Math.max(0, available - used) / gapCount;
  }
  used += between * gapCount;
  let cursor = 0;
  if (gravity === "center") cursor = Math.max(0, (available - used) / 2);
  if (gravity === "end") cursor = Math.max(0, available - used);
  children.forEach((child, index) => {
    const margin = margins[index];
    const size = sizes[index];
    const align = child.align || "start";
    if (vertical) {
      const crossSpace = Math.max(0, content.w - margin.left - margin.right);
      let cross = size.width;
      let crossPos = 0;
      if (align === "stretch") cross = crossSpace;
      else if (align === "center") crossPos = Math.max(0, (crossSpace - cross) / 2);
      else if (align === "end") crossPos = Math.max(0, crossSpace - cross);
      frames[child.id] = {
        x: content.x + margin.left + crossPos,
        y: content.y + cursor + margin.top,
        w: cross,
        h: size.height
      };
      cursor += margin.top + size.height + margin.bottom + between;
    } else {
      const crossSpace = Math.max(0, content.h - margin.top - margin.bottom);
      let cross = size.height;
      let crossPos = 0;
      if (align === "stretch") cross = crossSpace;
      else if (align === "center") crossPos = Math.max(0, (crossSpace - cross) / 2);
      else if (align === "end") crossPos = Math.max(0, crossSpace - cross);
      frames[child.id] = {
        x: content.x + cursor + margin.left,
        y: content.y + margin.top + crossPos,
        w: size.width,
        h: cross
      };
      cursor += margin.left + size.width + margin.right + between;
    }
  });
}

function layoutDock(children, content, scale, screen, frames) {
  let remaining = { ...content };
  for (const child of children) {
    const margin = insets(child.margin, scale);
    const avail = {
      width: Math.max(0, remaining.w - margin.left - margin.right),
      height: Math.max(0, remaining.h - margin.top - margin.bottom)
    };
    const size = resolveSize(child, avail, scale, screen);
    const dock = child.dock || "top";
    if (dock === "bottom") {
      const height = Math.min(size.height, avail.height);
      frames[child.id] = {
        x: remaining.x + margin.left,
        y: remaining.y + remaining.h - margin.bottom - height,
        w: avail.width,
        h: height
      };
      remaining = { ...remaining, h: Math.max(0, remaining.h - height - margin.top - margin.bottom) };
    } else if (dock === "left") {
      const width = Math.min(size.width, avail.width);
      frames[child.id] = { x: remaining.x + margin.left, y: remaining.y + margin.top, w: width, h: avail.height };
      const consumed = width + margin.left + margin.right;
      remaining = { x: remaining.x + consumed, y: remaining.y, w: Math.max(0, remaining.w - consumed), h: remaining.h };
    } else if (dock === "right") {
      const width = Math.min(size.width, avail.width);
      frames[child.id] = {
        x: remaining.x + remaining.w - margin.right - width,
        y: remaining.y + margin.top,
        w: width,
        h: avail.height
      };
      remaining = { ...remaining, w: Math.max(0, remaining.w - width - margin.left - margin.right) };
    } else if (dock === "fill") {
      frames[child.id] = { x: remaining.x + margin.left, y: remaining.y + margin.top, w: avail.width, h: avail.height };
      remaining = { ...remaining, w: 0, h: 0 };
    } else {
      const height = Math.min(Math.max(0, size.height), avail.height);
      frames[child.id] = { x: remaining.x + margin.left, y: remaining.y + margin.top, w: avail.width, h: height };
      const consumed = height + margin.top + margin.bottom;
      remaining = { x: remaining.x, y: remaining.y + consumed, w: remaining.w, h: Math.max(0, remaining.h - consumed) };
    }
  }
}

function layoutChildren(node, width, height, scale, screen, frames) {
  if (node.type !== "container") return;
  const pad = insets(node.padding, scale);
  const content = {
    x: pad.left,
    y: pad.top,
    w: Math.max(0, width - pad.left - pad.right),
    h: Math.max(0, height - pad.top - pad.bottom)
  };
  const children = node.children || [];
  const layout = node.layout || "absolute";
  if (layout === "linear") layoutLinear(node, children, content, scale, screen, frames);
  else if (layout === "dock") layoutDock(children, content, scale, screen, frames);
  else layoutAbsolute(children, content, scale, screen, frames);
  for (const child of children) {
    const frame = frames[child.id];
    if (frame) layoutChildren(child, frame.w, frame.h, scale, screen, frames);
  }
}

export function layoutDocument(doc) {
  const screen = {
    width: Number(doc.designWidth) || 375,
    height: Number(doc.designHeight) || 812
  };
  const frames = {};
  frames[doc.root.id] = { x: 0, y: 0, w: screen.width, h: screen.height };
  layoutChildren(doc.root, screen.width, screen.height, 1, screen, frames);
  return { screen, frames };
}

export function skipFrame(doc, screen) {
  const skip = doc.skip;
  const padH = Number(skip.paddingH ?? 12);
  const padV = Number(skip.paddingV ?? 6);
  const text = `${skip.text || "跳过"} ${doc.duration}`;
  const width = Math.max(64, text.length * (Number(skip.fontSize) || 13) * 0.7 + padH * 2);
  const height = (Number(skip.fontSize) || 13) + padV * 2 + 4;
  const ox = Number(skip.offsetX) || 0;
  const oy = Number(skip.offsetY) || 0;
  let x = screen.width - ox - width;
  let y = oy;
  if (skip.position === "topLeft") {
    x = ox;
    y = oy;
  } else if (skip.position === "bottomLeft") {
    x = ox;
    y = screen.height - oy - height;
  } else if (skip.position === "bottomRight") {
    x = screen.width - ox - width;
    y = screen.height - oy - height;
  }
  return { x, y, w: width, h: height };
}
