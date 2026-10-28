export function blankDocument() {
  return {
    schema: 1,
    designWidth: 375,
    designHeight: 812,
    duration: -1,
    skip: {
      enabled: true,
      visible: true,
      text: "跳过",
      position: "topRight",
      offsetX: 16,
      offsetY: 12,
      textColor: "#FFFFFF",
      backgroundColor: "#80000000",
      fontSize: 13,
      cornerRadius: 14,
      paddingH: 12,
      paddingV: 6
    },
    root: {
      id: "root",
      type: "container",
      layout: "absolute",
      size: { widthMode: "fullscreen", heightMode: "fullscreen" },
      backgroundColor: "#141414",
      children: []
    }
  };
}

export function createNode(type, parent, assets) {
  const id = "n" + Math.random().toString(36).slice(2, 8);
  const place = {};
  if (parent && parent.layout === "absolute") {
    place.x = 24;
    place.y = 24;
  }
  if (parent && parent.layout === "dock") {
    place.dock = "top";
  }
  if (type === "container") {
    return {
      id,
      type: "container",
      layout: "absolute",
      size: { widthMode: "fixed", heightMode: "fixed", width: 180, height: 120 },
      backgroundColor: "#292524",
      children: [],
      ...place
    };
  }
  if (type === "image") {
    const image = (assets || []).find((path) => /\.(png|jpe?g|gif|webp)$/i.test(path));
    return {
      id,
      type: "image",
      src: image ? `zip://${image}` : "zip://images/placeholder.png",
      contentMode: "aspectFill",
      size: { widthMode: "fixed", heightMode: "fixed", width: 160, height: 120 },
      ...place
    };
  }
  if (type === "button") {
    return {
      id,
      type: "button",
      text: "按钮",
      textColor: "#FFFFFF",
      fontSize: 16,
      backgroundColor: "#C2410C",
      cornerRadius: 8,
      size: { widthMode: "fixed", heightMode: "fixed", width: 160, height: 44 },
      click: { type: "openUrl", url: "https://example.com" },
      ...place
    };
  }
  return {
    id,
    type: "html",
    size: { widthMode: "fixed", heightMode: "fixed", width: 220, height: 64 },
    source: { type: "inline", html: "<p style=\"margin:0;color:#fff;font-family:sans-serif\">HTML</p>" },
    ...place
  };
}

export function findNode(node, id) {
  if (!node) return null;
  if (node.id === id) return node;
  for (const child of node.children || []) {
    const found = findNode(child, id);
    if (found) return found;
  }
  return null;
}

export function findParent(node, id) {
  for (const child of node.children || []) {
    if (child.id === id) return node;
    const nested = findParent(child, id);
    if (nested) return nested;
  }
  return null;
}
