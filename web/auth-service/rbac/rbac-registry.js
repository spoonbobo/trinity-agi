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

function getAllPermissions() {
  const reg = loadRegistry();
  return reg?.permissions || [];
}

function getPermissionActions() {
  return getAllPermissions().map(p => p.action);
}

function getPermissionsByTier(tier) {
  return getAllPermissions()
    .filter(p => p.tier === tier)
    .map(p => p.action);
}

function getRoleConfig(roleName) {
  const reg = loadRegistry();
  return reg?.roles?.[roleName] || null;
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

function isCommandAllowedForTier(command, tier) {
  const allowed = getTerminalCommands(tier);
  const baseCmd = command.split(' ')[0];
  return allowed.some(a => command.startsWith(a) || baseCmd === a.split(' ')[0]);
}

function getRoleTier(roleName) {
  const role = getRoleConfig(roleName);
  return role?.tier || 'safe';
}

module.exports = {
  loadRegistry,
  getAllPermissions,
  getPermissionActions,
  getPermissionsByTier,
  getRoleConfig,
  getTerminalCommands,
  isCommandAllowedForTier,
  getRoleTier,
};
