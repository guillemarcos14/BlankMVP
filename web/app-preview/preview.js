const previewButtons = document.querySelectorAll("[data-preview]");
const previewPanels = document.querySelectorAll("[data-preview-panel]");
const previewTargets = document.querySelectorAll("[data-preview-target]");
const targetButtonsWithReturn = document.querySelectorAll("[data-return-screen]");
const mainAction = document.querySelector("[data-main-action]");
const homeScreen = document.querySelector(".home-screen");
const mainMessage = document.querySelector("[data-main-message]");
const sessionMeta = document.querySelector("[data-session-meta]");
const onboardingPanels = document.querySelectorAll("[data-onboarding-step]");
const onboardingDots = document.querySelectorAll(".onboarding-dots span");
const onboardingNext = document.querySelector("[data-onboarding-next]");
const appCheckboxes = document.querySelectorAll("[data-app-checkbox]");
const saveAppsButton = document.querySelector("[data-save-apps]");
const appCountLabels = document.querySelectorAll("[data-app-count]");
const relinkButton = document.querySelector("[data-complete-relink]");
const relinkTitle = document.querySelector("[data-relink-title]");
const relinkCopy = document.querySelector("[data-relink-copy]");
const forgetButton = document.querySelector("[data-forget-nfc]");
const emergencyStartButton = document.querySelector("[data-emergency-start]");
const emergencyInput = document.querySelector("[data-emergency-input]");
const emergencyUnlock = document.querySelector("[data-emergency-unlock]");
const emergencyRemaining = document.querySelector("[data-emergency-remaining]");

let isBlankActive = false;
let timerActive = false;
let timerMinutes = 30;
let activeSeconds = 1472;
let onboardingStep = 0;
let returnScreen = "profile";
let nfcRelinked = false;
let emergencyUnlocksThisWeek = 0;

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
    mainAction.textContent = "Escanear NFC para salir";
    mainAction.disabled = false;
    sessionMeta.textContent = formatElapsed(activeSeconds);
  } else {
    mainMessage.innerHTML = "Vuelve cuando<br />quieras recuperar<br />silencio.";
    mainAction.textContent = "Iniciar Blank";
    mainAction.disabled = false;
    sessionMeta.textContent = `${selectedAppCount()} distracciones protegidas`;
  }
}

function formatElapsed(totalSeconds) {
  const hours = Math.floor(totalSeconds / 3600).toString().padStart(2, "0");
  const minutes = Math.floor((totalSeconds % 3600) / 60).toString().padStart(2, "0");
  const seconds = Math.floor(totalSeconds % 60).toString().padStart(2, "0");
  return `${hours}:${minutes}:${seconds}`;
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
  if (isBlankActive) {
    isBlankActive = false;
    timerActive = false;
  } else {
    isBlankActive = true;
    timerActive = false;
  }
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

function renderAppCount() {
  const count = selectedAppCount();
  appCountLabels.forEach((label) => {
    label.textContent = String(count);
  });
}

saveAppsButton.addEventListener("click", () => {
  renderAppCount();
  renderBlankState();
  setPreview(returnScreen);
});

appCheckboxes.forEach((checkbox) => {
  checkbox.addEventListener("change", () => {
    renderAppCount();
  });
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

function renderEmergencyUnlocks() {
  const remaining = Math.max(0, 3 - emergencyUnlocksThisWeek);
  emergencyRemaining.textContent = remaining > 0
    ? `Te quedan ${remaining} desbloqueos de emergencia esta semana.`
    : "Ya has usado tus 3 desbloqueos de emergencia esta semana.";
  emergencyUnlock.disabled = remaining <= 0 || emergencyInput.value.trim() !== "quiero desactivar blank aunque sea una mala idea";
}

emergencyInput.addEventListener("input", () => {
  renderEmergencyUnlocks();
});

emergencyUnlock.addEventListener("click", () => {
  if (isBlankActive && emergencyUnlocksThisWeek >= 3) return;
  if (isBlankActive) emergencyUnlocksThisWeek += 1;
  isBlankActive = false;
  renderBlankState();
  emergencyInput.value = "";
  renderEmergencyUnlocks();
  setPreview("home");
});

setPreview("onboarding");
setOnboardingStep(0);
renderAppCount();
renderBlankState();
renderEmergencyUnlocks();
