<script setup>
import { computed, onMounted, reactive, ref } from "vue";
import { api } from "./api";
import { blankDocument, createNode, findNode, findParent } from "./model";
import { layoutDocument, skipFrame } from "./layoutEngine";

const props = defineProps({ adId: { type: Number, required: true } });
const emit = defineEmits(["back"]);

const step = ref(1);
const error = ref("");
const busy = ref(false);
const name = ref("");
const ad = ref(null);
const doc = reactive(blankDocument());
const selectedId = ref("root");
const assets = ref([]);
const cdnUrl = ref("");
const linkSource = ref("server");
const startTime = ref("");
const endTime = ref("");
const durationMode = ref("5");
const customDuration = ref(-1);
const priority = ref(0);
const zoom = ref(0.72);

const selected = computed(() => findNode(doc.root, selectedId.value) || doc.root);
const parentNode = computed(() => findParent(doc.root, selected.value.id));
const laid = computed(() => layoutDocument(doc));
const skip = computed(() => skipFrame(doc, laid.value.screen));

function applyAd(payload) {
  ad.value = payload;
  name.value = payload.name || "";
  assets.value = payload.assets || [];
  cdnUrl.value = payload.packageUrl || "";
  linkSource.value = payload.packageSource || "server";
  priority.value = payload.priority || 0;
  startTime.value = toLocal(payload.startTime);
  endTime.value = toLocal(payload.endTime);
  if (payload.duration === 3 || payload.duration === 5 || payload.duration === 8) {
    durationMode.value = String(payload.duration);
  } else if (payload.duration != null) {
    durationMode.value = "custom";
    customDuration.value = payload.duration;
  }
  if (payload.layout) {
    Object.assign(doc, payload.layout);
    doc.root = payload.layout.root;
    doc.skip = payload.layout.skip;
    if (doc.skip.visible == null) doc.skip.visible = doc.skip.enabled !== false;
  }
}

async function load() {
  applyAd(await api(`/admin/api/ads/${props.adId}`));
}

function toLocal(iso) {
  if (!iso) return "";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  const pad = (value) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function chosenDuration() {
  if (durationMode.value === "custom") return Number(customDuration.value);
  return Number(durationMode.value);
}

async function upload(event) {
  error.value = "";
  const files = [...event.target.files];
  try {
    for (const file of files) {
      const folder = /\.(html?|css|js)$/i.test(file.name) ? "html" : "images";
      const body = new FormData();
      body.append("file", file);
      body.append("path", `${folder}/${file.name}`);
      await api(`/admin/api/ads/${props.adId}/assets`, { method: "POST", body });
    }
    await load();
  } catch (exception) {
    error.value = exception.message;
  }
  event.target.value = "";
}

function add(type) {
  const parent = selected.value.type === "container" ? selected.value : parentNode.value || doc.root;
  if (type === "image" && !assets.value.some((path) => /\.(png|jpe?g|gif|webp)$/i.test(path))) {
    error.value = "请先上传图片资源";
    return;
  }
  error.value = "";
  parent.children = parent.children || [];
  const node = createNode(type, parent, assets.value);
  parent.children.push(node);
  selectedId.value = node.id;
}

function removeSelected() {
  const parent = parentNode.value;
  if (!parent) return;
  parent.children = parent.children.filter((child) => child.id !== selected.value.id);
  selectedId.value = parent.id;
}

function move(delta) {
  const parent = parentNode.value;
  if (!parent) return;
  const index = parent.children.findIndex((child) => child.id === selected.value.id);
  const next = index + delta;
  if (next < 0 || next >= parent.children.length) return;
  const [item] = parent.children.splice(index, 1);
  parent.children.splice(next, 0, item);
}

function onPointerDown(event, node) {
  selectedId.value = node.id;
  const parent = findParent(doc.root, node.id);
  if (!parent || parent.layout !== "absolute") return;
  const originX = Number(node.x) || 0;
  const originY = Number(node.y) || 0;
  const startX = event.clientX;
  const startY = event.clientY;
  const movePointer = (ev) => {
    node.x = Math.round(originX + (ev.clientX - startX) / zoom.value);
    node.y = Math.round(originY + (ev.clientY - startY) / zoom.value);
  };
  const up = () => {
    window.removeEventListener("pointermove", movePointer);
    window.removeEventListener("pointerup", up);
  };
  window.addEventListener("pointermove", movePointer);
  window.addEventListener("pointerup", up);
}

async function storeAd() {
  busy.value = true;
  error.value = "";
  try {
    doc.duration = Number.isFinite(chosenDuration()) ? chosenDuration() : -1;
    doc.skip.visible = doc.skip.visible !== false;
    doc.skip.enabled = doc.skip.visible;
    applyAd(await api(`/admin/api/ads/${props.adId}/store`, {
      method: "POST",
      body: { name: name.value, layout: JSON.parse(JSON.stringify(doc)) }
    }));
    step.value = 2;
  } catch (exception) {
    error.value = exception.message;
  } finally {
    busy.value = false;
  }
}

async function saveLink() {
  busy.value = true;
  error.value = "";
  try {
    const body = linkSource.value === "cdn"
      ? { source: "cdn", url: cdnUrl.value }
      : { source: "server" };
    applyAd(await api(`/admin/api/ads/${props.adId}/link`, { method: "PUT", body }));
  } catch (exception) {
    error.value = exception.message;
  } finally {
    busy.value = false;
  }
}

async function publish() {
  busy.value = true;
  error.value = "";
  try {
    const duration = chosenDuration();
    if (!Number.isInteger(duration)) {
      throw new Error("展示时长必须是整数");
    }
    applyAd(await api(`/admin/api/ads/${props.adId}/publish`, {
      method: "POST",
      body: {
        startTime: new Date(startTime.value).toISOString(),
        endTime: new Date(endTime.value).toISOString(),
        duration,
        priority: Number(priority.value) || 0
      }
    }));
    error.value = "";
    alert("已发布");
  } catch (exception) {
    error.value = exception.message;
  } finally {
    busy.value = false;
  }
}

function assetUrl(path) {
  return `/admin/api/ads/${props.adId}/assets/file?path=${encodeURIComponent(path)}`;
}

function imagePath(node) {
  const src = node.src || "";
  return src.startsWith("zip://") ? src.slice(6) : "";
}

function ensureClick(node) {
  if (!node.click) node.click = { type: "openUrl", url: "https://example.com" };
  return node.click;
}

function ensureSource(node) {
  if (!node.source) node.source = { type: "inline", html: "" };
  return node.source;
}

onMounted(load);
</script>

<template>
  <div>
    <header class="topbar">
      <strong>{{ name || "广告" }}</strong>
      <button class="ghost" @click="emit('back')">返回列表</button>
    </header>
    <div class="steps">
      <div>
        <button :class="{ active: step === 1 }" @click="step = 1">1 规划样式</button>
        <button :class="{ active: step === 2 }" @click="step = 2">2 素材链接</button>
        <button :class="{ active: step === 3 }" @click="step = 3">3 发布</button>
      </div>
      <span class="muted" style="color:#d6d3d1">{{ ad?.status === 'published' ? '已发布' : ad?.packageMd5 ? '已生成 zip' : '未存储' }}</span>
    </div>
    <p v-if="error" class="error" style="margin: 12px 20px">{{ error }}</p>

    <div v-show="step === 1" class="workspace">
      <aside class="panel">
        <label>名称</label>
        <input v-model="name" />
        <p class="muted">上传标准资源，再在画布上排版。</p>
        <input type="file" multiple accept=".png,.jpg,.jpeg,.gif,.webp,.html,.htm,.css,.js,.svg" @change="upload" />
        <div class="stack" style="margin-top: 12px">
          <button @click="add('container')">添加容器</button>
          <button @click="add('image')">添加图片</button>
          <button @click="add('button')">添加按钮</button>
          <button @click="add('html')">添加 HTML</button>
        </div>
        <h2 style="margin-top: 20px; font-size: 16px">已上传</h2>
        <div v-for="path in assets" :key="path" class="asset"><span>{{ path }}</span></div>
        <button class="primary" style="margin-top: 16px; width: 100%" :disabled="busy" @click="storeAd">存储广告</button>
      </aside>
      <div class="stage">
        <div class="board" :style="{ width: laid.screen.width + 'px', height: laid.screen.height + 'px', transform: `scale(${zoom})`, background: doc.root.backgroundColor }">
          <NodeBox
            :node="doc.root"
            :frames="laid.frames"
            :selected-id="selectedId"
            :ad-id="adId"
            @pick="onPointerDown"
          />
          <div
            v-if="doc.skip.visible !== false"
            class="skip-preview"
            :style="{
              left: skip.x + 'px',
              top: skip.y + 'px',
              minWidth: skip.w + 'px',
              height: skip.h + 'px',
              color: doc.skip.textColor,
              background: doc.skip.backgroundColor,
              borderRadius: doc.skip.cornerRadius + 'px',
              fontSize: doc.skip.fontSize + 'px'
            }"
          >{{ doc.skip.text }} 5</div>
        </div>
      </div>
      <aside class="panel">
        <template v-if="selected.id === 'root' || selected.type === 'container'">
          <label>布局</label>
          <select v-model="selected.layout">
            <option value="absolute">坐标</option>
            <option value="linear">线性</option>
            <option value="dock">停靠</option>
          </select>
          <template v-if="selected.layout === 'linear'">
            <label>方向</label>
            <select v-model="selected.direction">
              <option value="vertical">垂直</option>
              <option value="horizontal">水平</option>
            </select>
            <label>间距</label>
            <input v-model.number="selected.spacing" type="number" />
            <label>对齐</label>
            <select v-model="selected.gravity">
              <option value="start">起点</option>
              <option value="center">居中</option>
              <option value="end">终点</option>
              <option value="spaceBetween">两端</option>
            </select>
          </template>
        </template>
        <p class="muted">{{ selected.type }} · {{ selected.id }}</p>
        <template v-if="parentNode && parentNode.layout === 'absolute'">
          <div class="row">
            <div><label>X</label><input v-model.number="selected.x" type="number" /></div>
            <div><label>Y</label><input v-model.number="selected.y" type="number" /></div>
          </div>
        </template>
        <template v-if="parentNode && parentNode.layout === 'dock'">
          <label>停靠</label>
          <select v-model="selected.dock">
            <option value="top">上</option>
            <option value="bottom">下</option>
            <option value="left">左</option>
            <option value="right">右</option>
            <option value="fill">填充</option>
          </select>
        </template>
        <template v-if="parentNode && parentNode.layout === 'linear'">
          <label>权重</label>
          <input v-model.number="selected.weight" type="number" min="0" />
          <label>交叉轴</label>
          <select v-model="selected.align">
            <option value="start">起点</option>
            <option value="center">居中</option>
            <option value="end">终点</option>
            <option value="stretch">拉伸</option>
          </select>
          <div class="row" style="margin-top: 8px">
            <button class="ghost" @click="move(-1)">上移</button>
            <button class="ghost" @click="move(1)">下移</button>
          </div>
        </template>
        <div class="row">
          <div>
            <label>宽</label>
            <select v-model="selected.size.widthMode">
              <option v-if="selected.type !== 'html'" value="wrap">自适应</option>
              <option value="fixed">固定</option>
              <option value="match">撑满</option>
              <option value="percent">百分比</option>
              <option value="fullscreen">全屏</option>
            </select>
            <input v-if="selected.size.widthMode === 'fixed' || selected.size.widthMode === 'percent'" v-model.number="selected.size.width" type="number" />
          </div>
          <div>
            <label>高</label>
            <select v-model="selected.size.heightMode">
              <option v-if="selected.type !== 'html'" value="wrap">自适应</option>
              <option value="fixed">固定</option>
              <option value="match">撑满</option>
              <option value="percent">百分比</option>
              <option value="fullscreen">全屏</option>
            </select>
            <input v-if="selected.size.heightMode === 'fixed' || selected.size.heightMode === 'percent'" v-model.number="selected.size.height" type="number" />
          </div>
        </div>
        <label>背景色</label>
        <input v-model="selected.backgroundColor" placeholder="#RRGGBB 或 #AARRGGBB" />
        <template v-if="selected.type === 'image'">
          <label>图片</label>
          <select :value="imagePath(selected)" @change="selected.src = 'zip://' + $event.target.value">
            <option v-for="path in assets.filter(item => /\.(png|jpe?g|gif|webp|svg)$/i.test(item))" :key="path" :value="path">{{ path }}</option>
          </select>
          <label>缩放</label>
          <select v-model="selected.contentMode">
            <option value="aspectFill">铺满裁切</option>
            <option value="fit">适应</option>
            <option value="fill">拉伸</option>
          </select>
        </template>
        <template v-if="selected.type === 'button'">
          <label>文案</label>
          <input v-model="selected.text" />
          <label>字色</label>
          <input v-model="selected.textColor" />
          <label>字号</label>
          <input v-model.number="selected.fontSize" type="number" />
          <label>圆角</label>
          <input v-model.number="selected.cornerRadius" type="number" />
        </template>
        <template v-if="selected.type === 'html'">
          <label>来源</label>
          <select v-model="ensureSource(selected).type">
            <option value="inline">写在 JSON 里</option>
            <option value="zip">素材包内文件</option>
          </select>
          <textarea v-if="selected.source.type === 'inline'" v-model="selected.source.html"></textarea>
          <select v-else v-model="selected.source.path">
            <option v-for="path in assets.filter(item => /\.html?$/i.test(item))" :key="path" :value="path">{{ path }}</option>
          </select>
        </template>
        <template v-if="selected.type === 'button' || selected.type === 'image'">
          <label>点击</label>
          <select v-model="ensureClick(selected).type">
            <option value="openUrl">打开链接</option>
            <option value="dismiss">关闭启屏</option>
          </select>
          <input v-if="selected.click.type === 'openUrl'" v-model="selected.click.url" placeholder="https://" />
        </template>
        <template v-if="selected.id === 'root'">
          <h2 style="margin-top: 18px; font-size: 16px">倒计时按钮</h2>
          <label><input type="checkbox" v-model="doc.skip.visible" /> 显示</label>
          <label>文案</label>
          <input v-model="doc.skip.text" />
          <label>位置</label>
          <select v-model="doc.skip.position">
            <option value="topRight">右上</option>
            <option value="topLeft">左上</option>
            <option value="bottomRight">右下</option>
            <option value="bottomLeft">左下</option>
          </select>
          <div class="row">
            <div><label>水平偏移</label><input v-model.number="doc.skip.offsetX" type="number" /></div>
            <div><label>垂直偏移</label><input v-model.number="doc.skip.offsetY" type="number" /></div>
          </div>
          <label>字色</label>
          <input v-model="doc.skip.textColor" />
          <label>底色</label>
          <input v-model="doc.skip.backgroundColor" />
          <div class="row">
            <div><label>字号</label><input v-model.number="doc.skip.fontSize" type="number" /></div>
            <div><label>圆角</label><input v-model.number="doc.skip.cornerRadius" type="number" /></div>
          </div>
        </template>
        <button v-if="selected.id !== 'root'" class="danger" style="margin-top: 16px" @click="removeSelected">删除元素</button>
      </aside>
    </div>

    <section v-show="step === 2" class="step-page">
      <h2>把 zip 放到 CDN</h2>
      <p class="muted">存储广告后，服务器把上传的资源打成一个 zip。下载后自行保存到 CDN，再把链接填回来。测试可以直接用这台服务器上的地址。</p>
      <p v-if="ad?.packageMd5">MD5 {{ ad.packageMd5 }}</p>
      <p><a :href="`/api/v1/ads/${adId}/package`">下载 zip</a></p>
      <div class="choice">
        <button :class="{ on: linkSource === 'server' }" @click="linkSource = 'server'">使用服务器地址测试</button>
        <button :class="{ on: linkSource === 'cdn' }" @click="linkSource = 'cdn'">填写 CDN 链接</button>
      </div>
      <template v-if="linkSource === 'cdn'">
        <label>CDN https 链接</label>
        <input v-model="cdnUrl" placeholder="https://cdn.example.com/splash/ad.zip" />
      </template>
      <button class="primary" :disabled="busy || !ad?.packageMd5" @click="saveLink">校验并保存链接</button>
      <p v-if="ad?.packageVerified" class="muted">链接已通过校验。</p>
    </section>

    <section v-show="step === 3" class="step-page">
      <h2>发布</h2>
      <label>生效开始</label>
      <input v-model="startTime" type="datetime-local" />
      <label>生效结束</label>
      <input v-model="endTime" type="datetime-local" />
      <label>展示时长</label>
      <div class="choice">
        <button :class="{ on: durationMode === '3' }" @click="durationMode = '3'">3 秒</button>
        <button :class="{ on: durationMode === '5' }" @click="durationMode = '5'">5 秒</button>
        <button :class="{ on: durationMode === '8' }" @click="durationMode = '8'">8 秒</button>
        <button :class="{ on: durationMode === 'custom' }" @click="durationMode = 'custom'">自定义</button>
      </div>
      <input v-if="durationMode === 'custom'" v-model.number="customDuration" type="number" step="1" />
      <p class="muted">整数。等于 0 会立刻询问跳转，负数不会自动跳转。</p>
      <label>优先级</label>
      <input v-model.number="priority" type="number" step="1" />
      <button class="primary" style="margin-top: 16px" :disabled="busy" @click="publish">发布</button>
    </section>
  </div>
</template>

<script>
import { defineComponent, h } from "vue";

const NodeBox = defineComponent({
  name: "NodeBox",
  props: {
    node: { type: Object, required: true },
    frames: { type: Object, required: true },
    selectedId: { type: String, required: true },
    adId: { type: Number, required: true },
    root: { type: Boolean, default: true }
  },
  emits: ["pick"],
  setup(props, { emit }) {
    return () => {
      const frame = props.frames[props.node.id] || { x: 0, y: 0, w: 0, h: 0 };
      const style = props.root
        ? { position: "relative", width: frame.w + "px", height: frame.h + "px" }
        : {
            position: "absolute",
            left: frame.x + "px",
            top: frame.y + "px",
            width: frame.w + "px",
            height: frame.h + "px",
            background: props.node.type === "button" ? props.node.backgroundColor : props.node.backgroundColor,
            color: props.node.textColor,
            borderRadius: (props.node.cornerRadius || 0) + "px",
            fontSize: (props.node.fontSize || 14) + "px"
          };
      const children = [];
      if (props.node.type === "image") {
        const path = (props.node.src || "").replace(/^zip:\/\//, "");
        children.push(h("img", { src: `/admin/api/ads/${props.adId}/assets/file?path=${encodeURIComponent(path)}` }));
      } else if (props.node.type === "button") {
        children.push(h("button", { class: "face", type: "button" }, props.node.text));
      } else if (props.node.type === "html" && props.node.source?.type === "inline") {
        children.push(h("div", { innerHTML: props.node.source.html || "" }));
      } else if (props.node.type === "html" && props.node.source?.path) {
        children.push(h("iframe", { src: `/admin/api/ads/${props.adId}/assets/file?path=${encodeURIComponent(props.node.source.path)}` }));
      }
      for (const child of props.node.children || []) {
        children.push(h(NodeBox, {
          node: child,
          frames: props.frames,
          selectedId: props.selectedId,
          adId: props.adId,
          root: false,
          onPick: (event, node) => emit("pick", event, node)
        }));
      }
      return h("div", {
        class: ["node", { selected: props.selectedId === props.node.id }],
        style,
        onPointerdown: (event) => {
          event.stopPropagation();
          emit("pick", event, props.node);
        }
      }, children);
    };
  }
});

export default { components: { NodeBox } };
</script>
