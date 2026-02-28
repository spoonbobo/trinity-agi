const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const REGISTRY_PATH = path.join(__dirname, '..', 'rbac', 'permissions.yaml');

let registry = null;

function loadRegistry() {
  if (registry) return registry;
  
  try {
    const content = fs.readFileSync(REGISTRY_PATH, 'utf8');
    registry = yaml.load(content);
    return registry;
  } catch (err) {
    console.error('[rbac-registry] Failed to load permissions.yaml:', err.message);
    return null;
  }
}

function getTerminalCommands(tier) {
  const reg = loadRegistry();
  const allTiers = ['safe', 'standard', 'privileged'];
  const tierIndex = allTiers.indexOf(tier);
  
  if (tierIndex === -1) return [];
  
  const allowed = [];
  for (let i = 0; i <= tierIndex; i++) {
    const tierCommands = reg?.terminal?.[allTiers[i]] || [];
    allowed.push(...tierCommands);
  }
  return allowed;
}

function getRoleTier(roleName) {
  const reg = loadRegistry();
  const role = reg?.roles?.[roleName];
  return role?.tier || 'safe';
}

function isCommandAllowedForTier(cleanCmd, tier) {
  const allowed = getTerminalCommands(tier);
  const baseCmd = cleanCmd.split(' ')[0];
  return allowed.some(a => cleanCmd.startsWith(a) || baseCmd === a.split(' ')[0]);
}

function getAllowedCommands() {
  const reg = loadRegistry();
  const all = [];
  ['safe', 'standard', 'privileged'].forEach(tier => {
    all.push(...(reg?.terminal?.[tier] || []));
  });
  return [...new Set(all)];
}

function getInteractiveCommands() {
  return ['configure', 'onboard', 'channels login'];
}

module.exports = {
  loadRegistry,
  getTerminalCommands,
  getRoleTier,
  isCommandAllowedForTier,
  getAllowedCommands,
  getInteractiveCommands,
};
