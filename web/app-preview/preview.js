const previewButtons = document.querySelectorAll("[data-preview]");
const previewPanels = document.querySelectorAll("[data-preview-panel]");
const previewTargets = document.querySelectorAll("[data-preview-target]");
const targetButtonsWithReturn = document.querySelectorAll("[data-return-screen]");
const mainAction = document.querySelector("[data-main-action]");
const homeScreen = document.querySelector(".home-screen");
const mainMessage = document.querySelector("[data-main-message]");
const onboardingPanels = document.querySelectorAll("[data-onboarding-step]");
const onboardingDots = document.querySelectorAll(".onboarding-dots span");
const onboardingNext = document.querySelector("[data-onboarding-next]");
const appCheckboxes = document.querySelectorAll("[data-app-checkbox]");
const saveAppsButton = document.querySelector("[data-save-apps]");
const appCountLabels = document.querySelectorAll("[data-app-count]");
const currentModeNameLabels = document.querySelectorAll("[data-current-mode-name]");
const modeList = document.querySelector("[data-mode-list]");
const newModeInput = document.querySelector("[data-new-mode-input]");
const newModeAppCheckboxes = document.querySelectorAll("[data-new-mode-app]");
const openCreateModeButton = document.querySelector("[data-open-create-mode]");
const createModeButton = document.querySelector("[data-create-mode]");
const createModeWindow = document.querySelector("[data-create-mode-window]");
const cancelCreateModeButton = document.querySelector("[data-cancel-create-mode]");
const relinkButton = document.querySelector("[data-complete-relink]");
const relinkTitle = document.querySelector("[data-relink-title]");
const relinkCopy = document.querySelector("[data-relink-copy]");
const forgetButton = document.querySelector("[data-forget-nfc]");
const emergencyStartButton = document.querySelector("[data-emergency-start]");
const emergencyInput = document.querySelector("[data-emergency-input]");
const emergencyUnlock = document.querySelector("[data-emergency-unlock]");

let isBlankActive = false;
let onboardingStep = 0;
let returnScreen = "profile";
let nfcRelinked = false;
let currentModeId = "daily";
let editingModeId = null;
let openModeMenuId = null;
let isCreateModeWindowOpen = false;
let modes = [
  { id: "daily", name: "Rutina diaria", apps: ["Instagram", "TikTok", "YouTube"] },
  { id: "study", name: "Estudio", apps: ["Instagram", "TikTok", "Reddit", "X"] },
  { id: "night", name: "Noche", apps: ["YouTube", "Reddit"] },
];

function setPreview(screenName) {
  previewButtons.forEach((button) => {
    const isActive = button.dataset.preview === screenName;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-selected", String(isActive));
  });

  previewPanels.forEach((panel) => {
    panel.classList.toggle("is-active", panel.dataset.previewPanel === screenName);
  });
}

function renderBlankState() {
  homeScreen.classList.toggle("is-blank-active", isBlankActive);

  if (isBlankActive) {
    mainMessage.textContent = "Hoy ya elegiste estar fuera del bucle.";
    mainAction.textContent = "Usa tu NFC para salir";
    mainAction.disabled = true;
  } else {
    mainMessage.innerHTML = "Vuelve cuando<br />quieras recuperar<br />silencio.";
    mainAction.textContent = "Iniciar Blank";
    mainAction.disabled = false;
  }
}

function setOnboardingStep(nextStep) {
  onboardingStep = Math.max(0, Math.min(nextStep, onboardingPanels.length - 1));

  onboardingPanels.forEach((panel) => {
    panel.hidden = Number(panel.dataset.onboardingStep) !== onboardingStep;
    panel.classList.toggle("is-active", Number(panel.dataset.onboardingStep) === onboardingStep);
  });

  onboardingDots.forEach((dot, index) => {
    dot.classList.toggle("is-current", index === onboardingStep);
  });

  onboardingNext.textContent = onboardingStep === onboardingPanels.length - 1
    ? "Entrar en Blank"
    : "Continuar";
}

previewButtons.forEach((button) => {
  button.addEventListener("click", () => setPreview(button.dataset.preview));
});

previewTargets.forEach((button) => {
  button.addEventListener("click", () => {
    setPreview(button.dataset.previewTarget);
  });
});

targetButtonsWithReturn.forEach((button) => {
  button.addEventListener("click", () => {
    returnScreen = button.dataset.returnScreen || "profile";
  });
});

mainAction.addEventListener("click", () => {
  if (isBlankActive) return;
  isBlankActive = true;
  renderBlankState();
});

onboardingNext.addEventListener("click", () => {
  if (onboardingStep === onboardingPanels.length - 1) {
    setPreview("home");
    setOnboardingStep(0);
    return;
  }

  setOnboardingStep(onboardingStep + 1);
});

function selectedAppCount() {
  return [...appCheckboxes].filter((checkbox) => checkbox.checked).length;
}

function currentMode() {
  return modes.find((mode) => mode.id === currentModeId) || modes[0];
}

function appNamesFromCheckboxes() {
  return [...appCheckboxes]
    .filter((checkbox) => checkbox.checked)
    .map((checkbox) => checkbox.closest("label").querySelector("span").textContent.trim());
}

function appNamesFromCreateCheckboxes() {
  return [...newModeAppCheckboxes]
    .filter((checkbox) => checkbox.checked)
    .map((checkbox) => checkbox.closest("label").querySelector("span").textContent.trim());
}

function syncCheckboxesFromMode() {
  const apps = new Set(currentMode().apps);
  appCheckboxes.forEach((checkbox) => {
    const appName = checkbox.closest("label").querySelector("span").textContent.trim();
    checkbox.checked = apps.has(appName);
  });
}

function resetCreateModeWindow() {
  newModeInput.value = "";
  newModeAppCheckboxes.forEach((checkbox, index) => {
    checkbox.checked = index < 2;
  });
}

function renderCreateModeWindow() {
  createModeWindow.hidden = !isCreateModeWindowOpen;
}

function renderAppCount() {
  const count = currentMode().apps.length;
  appCountLabels.forEach((label) => {
    label.textContent = String(count);
  });
}

function renderModes() {
  const selected = currentMode();
  currentModeNameLabels.forEach((label) => {
    label.textContent = selected.name;
  });

  modeList.innerHTML = "";
  modes.forEach((mode) => {
    const isEditing = editingModeId === mode.id;
    const row = document.createElement("div");
    row.className = mode.id === currentModeId ? "mode-row is-selected" : "mode-row";
    row.classList.toggle("has-open-menu", openModeMenuId === mode.id);
    row.classList.toggle("is-editing", isEditing);
    row.innerHTML = isEditing ? `
      <div class="mode-row-main mode-row-edit">
        <label>
          <span>Nombre</span>
          <input type="text" value="${mode.name}" data-inline-mode-input="${mode.id}" />
        </label>
      </div>
      <div class="mode-row-menu mode-row-edit-actions">
        <button type="button" data-inline-mode-save="${mode.id}">Guardar nombre</button>
        <button type="button" data-inline-mode-cancel="${mode.id}">Cancelar</button>
      </div>
    ` : `
      <div class="mode-row-main">
        <div class="mode-row-copy">
          <span>${mode.name}</span>
          <strong>${mode.apps.length} apps</strong>
        </div>
        <button class="mode-menu-button" type="button" aria-label="Opciones de ${mode.name}" aria-expanded="${openModeMenuId === mode.id}" data-mode-menu="${mode.id}">&#8942;</button>
      </div>
      <div class="mode-row-menu" ${openModeMenuId === mode.id ? "" : "hidden"}>
        <button type="button" data-mode-edit-name="${mode.id}">Editar nombre</button>
        <button type="button" data-mode-edit-apps="${mode.id}">Editar apps</button>
        <button type="button" data-mode-delete="${mode.id}">Eliminar</button>
      </div>
    `;

    row.addEventListener("click", (event) => {
      if (event.target.closest("button")) return;
      if (event.target.closest("input")) return;
      currentModeId = mode.id;
      openModeMenuId = null;
      editingModeId = null;
      syncCheckboxesFromMode();
      renderModes();
      renderAppCount();
    });

    if (isEditing) {
      const input = row.querySelector("[data-inline-mode-input]");
      row.querySelector("[data-inline-mode-save]").addEventListener("click", () => {
        const name = input.value.trim();
        if (!name) return;

        mode.name = name;
        editingModeId = null;
        openModeMenuId = null;
        renderModes();
      });
      row.querySelector("[data-inline-mode-cancel]").addEventListener("click", () => {
        editingModeId = null;
        openModeMenuId = null;
        renderModes();
      });
      modeList.appendChild(row);
      return;
    }

    row.querySelector("[data-mode-menu]").addEventListener("click", () => {
      openModeMenuId = openModeMenuId === mode.id ? null : mode.id;
      renderModes();
    });

    row.querySelector("[data-mode-edit-name]").addEventListener("click", () => {
      currentModeId = mode.id;
      editingModeId = mode.id;
      openModeMenuId = null;
      syncCheckboxesFromMode();
      renderAppCount();
      renderModes();
    });

    row.querySelector("[data-mode-edit-apps]").addEventListener("click", () => {
      currentModeId = mode.id;
      openModeMenuId = null;
      returnScreen = "modes";
      syncCheckboxesFromMode();
      renderModes();
      renderAppCount();
      setPreview("apps");
    });

    row.querySelector("[data-mode-delete]").addEventListener("click", () => {
      if (modes.length === 1) return;
      modes = modes.filter((candidate) => candidate.id !== mode.id);
      if (currentModeId === mode.id) {
        currentModeId = modes[0].id;
        syncCheckboxesFromMode();
      }
      if (editingModeId === mode.id) {
        editingModeId = null;
      }
      openModeMenuId = null;
      renderModes();
      renderAppCount();
    });

    modeList.appendChild(row);
  });
}

saveAppsButton.addEventListener("click", () => {
  currentMode().apps = appNamesFromCheckboxes();
  renderAppCount();
  renderModes();
  setPreview(returnScreen);
});

appCheckboxes.forEach((checkbox) => {
  checkbox.addEventListener("change", () => {
    currentMode().apps = appNamesFromCheckboxes();
    renderAppCount();
    renderModes();
  });
});

openCreateModeButton.addEventListener("click", () => {
  isCreateModeWindowOpen = true;
  openModeMenuId = null;
  editingModeId = null;
  resetCreateModeWindow();
  renderCreateModeWindow();
  newModeInput.focus();
});

cancelCreateModeButton.addEventListener("click", () => {
  isCreateModeWindowOpen = false;
  renderCreateModeWindow();
});

createModeButton.addEventListener("click", () => {
  const name = newModeInput.value.trim();
  if (!name) return;

  const id = `mode-${Date.now()}`;
  modes.push({ id, name, apps: appNamesFromCreateCheckboxes() });
  currentModeId = id;
  openModeMenuId = null;
  editingModeId = null;
  isCreateModeWindowOpen = false;
  newModeInput.value = "";
  syncCheckboxesFromMode();
  renderModes();
  renderCreateModeWindow();
  renderAppCount();
});

relinkButton.addEventListener("click", () => {
  if (nfcRelinked) {
    setPreview("profile");
    return;
  }

  nfcRelinked = true;
  relinkTitle.textContent = "Etiqueta actualizada.";
  relinkCopy.textContent = "Tu nueva pieza f\u00edsica ya controla Blank.";
  relinkButton.textContent = "Volver a ajustes";
});

forgetButton.addEventListener("click", () => {
  isBlankActive = false;
  renderBlankState();
  setOnboardingStep(0);
  setPreview("onboarding");
});

emergencyStartButton.addEventListener("click", () => {
  setPreview("home");
});

emergencyInput.addEventListener("input", () => {
  emergencyUnlock.disabled = emergencyInput.value.trim() !== "quiero desactivar blank aunque sea una mala idea";
});

emergencyUnlock.addEventListener("click", () => {
  isBlankActive = false;
  renderBlankState();
  emergencyInput.value = "";
  emergencyUnlock.disabled = true;
  setPreview("home");
});

setPreview("onboarding");
setOnboardingStep(0);
syncCheckboxesFromMode();
renderModes();
renderCreateModeWindow();
renderAppCount();
renderBlankState();
