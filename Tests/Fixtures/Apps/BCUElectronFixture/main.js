const { app, BrowserWindow } = require("electron");
const path = require("node:path");
app.commandLine.appendSwitch("force-renderer-accessibility");
app.setName("BCU Electron Fixture");
function createWindow() {
  const window = new BrowserWindow({
    width: 900, height: 720, show: false, title: "BCU Electron Fixture",
    webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true }
  });
  window.loadFile(path.join(__dirname, "index.html"));
  window.once("ready-to-show", () => { window.show(); console.log(`BCU_FIXTURE_READY pid=${process.pid}`); });
}
app.whenReady().then(createWindow);
app.on("window-all-closed", () => app.quit());
