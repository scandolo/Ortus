// Preload bridge — exposes a thin, typed-ish API to renderers without
// nodeIntegration. All mutations flow through `ortus.dispatch(...)`;
// state arrives via the `state:update` push channel.

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('ortus', {
  getState: () => ipcRenderer.invoke('state:get'),
  dispatch: (action, payload) => ipcRenderer.invoke('action', action, payload),
  onState: (cb) => {
    const handler = (_e, snapshot) => cb(snapshot);
    ipcRenderer.on('state:update', handler);
    return () => ipcRenderer.removeListener('state:update', handler);
  },
  onChannel: (channel, cb) => {
    const handler = (_e, payload) => cb(payload);
    ipcRenderer.on(channel, handler);
    return () => ipcRenderer.removeListener(channel, handler);
  },
});
