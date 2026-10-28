<script setup>
import { onMounted, ref } from "vue";
import { api } from "./api";
import Editor from "./Editor.vue";

const screen = ref("login");
const ads = ref([]);
const currentId = ref(null);
const error = ref("");
const username = ref("admin");
const password = ref("admin");
const draftName = ref("");
const draftKey = ref("default");

async function refresh() {
  ads.value = await api("/admin/api/ads");
}

async function boot() {
  try {
    await api("/admin/api/me");
    await refresh();
    screen.value = "list";
  } catch {
    screen.value = "login";
  }
}

async function login() {
  error.value = "";
  try {
    await api("/admin/api/login", { method: "POST", body: { username: username.value, password: password.value } });
    await refresh();
    screen.value = "list";
  } catch (exception) {
    error.value = exception.message;
  }
}

async function createAd() {
  error.value = "";
  try {
    const ad = await api("/admin/api/ads", {
      method: "POST",
      body: { name: draftName.value || "未命名广告", appKey: draftKey.value || "default" }
    });
    currentId.value = ad.id;
    screen.value = "editor";
  } catch (exception) {
    error.value = exception.message;
  }
}

async function removeAd(id) {
  if (!window.confirm("删除这条广告？")) return;
  await api(`/admin/api/ads/${id}`, { method: "DELETE" });
  await refresh();
}

function statusText(status) {
  if (status === "published") return "已发布";
  if (status === "stored") return "已存储";
  return "草稿";
}

onMounted(boot);
</script>

<template>
  <div class="app-shell">
    <section v-if="screen === 'login'" class="login">
      <form class="card" @submit.prevent="login">
        <h1>启屏广告</h1>
        <p class="muted">登录后编排样式、生成素材包并发布。</p>
        <label>账号</label>
        <input v-model="username" autocomplete="username" />
        <label>口令</label>
        <input v-model="password" type="password" autocomplete="current-password" />
        <p v-if="error" class="error">{{ error }}</p>
        <button class="primary" type="submit" style="margin-top: 16px; width: 100%">登录</button>
      </form>
    </section>

    <section v-else-if="screen === 'list'">
      <header class="topbar">
        <strong>广告列表</strong>
        <button class="ghost" @click="api('/admin/api/logout', { method: 'POST' }).then(() => screen = 'login')">退出</button>
      </header>
      <div class="list">
        <div class="card" style="width: 100%; margin-bottom: 16px">
          <h2>新建广告</h2>
          <div class="row">
            <input v-model="draftName" placeholder="名称" />
            <input v-model="draftKey" placeholder="appKey，默认 default" />
            <button class="primary" @click="createAd">创建</button>
          </div>
          <p v-if="error" class="error">{{ error }}</p>
        </div>
        <table>
          <thead>
            <tr>
              <th>名称</th>
              <th>状态</th>
              <th>生效时间</th>
              <th>展示秒数</th>
              <th>曝光</th>
              <th>点击</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="ad in ads" :key="ad.id">
              <td>{{ ad.name }}</td>
              <td>{{ statusText(ad.status) }}</td>
              <td>{{ ad.startTime || "—" }}<br />{{ ad.endTime || "" }}</td>
              <td>{{ ad.duration ?? "—" }}</td>
              <td>{{ ad.impressionCount }}</td>
              <td>{{ ad.clickCount }}</td>
              <td class="row">
                <button class="primary" @click="currentId = ad.id; screen = 'editor'">编辑</button>
                <button class="danger" @click="removeAd(ad.id)">删除</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <Editor v-else :ad-id="currentId" @back="screen = 'list'; refresh()" />
  </div>
</template>
