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
  // Support both tier names (safe/standard/privileged) and role names (guest/user/admin)
  const tierToRoles = { safe: ['guest'], standard: ['guest', 'user'], privileged: ['guest', 'user', 'admin'] };
  const matchRoles = tierToRoles[tier];
  if (matchRoles) {
    return getAllPermissions()
      .filter(p => matchRoles.includes(p.tier))
      .map(p => p.action);
  }
  // Fallback: match directly against tier field value
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
  const cleanCmd = command.replace(/^openclaw\s+/, '').trim();
  const allowed = getTerminalCommands(tier);
  const allAbove = getAllCommandsAboveTier(tier);

  // Find the most specific (longest) matching entry across all tiers
  let bestMatch = null;
  let bestLen = -1;
  for (const a of [...allowed, ...allAbove]) {
    if (cleanCmd === a || cleanCmd.startsWith(a + ' ')) {
      if (a.length > bestLen) {
        bestMatch = a;
        bestLen = a.length;
      }
    }
  }

  if (!bestMatch) return false;

  // The most specific match must be in the allowed set for this tier
  return allowed.includes(bestMatch);
}

function getAllCommandsAboveTier(tier) {
  const reg = loadRegistry();
  const allTiers = ['safe', 'standard', 'privileged'];
  const tierIndex = allTiers.indexOf(tier);
  const above = [];
  for (let i = tierIndex + 1; i < allTiers.length; i++) {
    above.push(...(reg?.terminal?.[allTiers[i]] || []));
  }
  return above;
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
