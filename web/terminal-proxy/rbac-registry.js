const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const REGISTRY_PATH = path.join(__dirname, 'rbac', 'permissions.yaml');

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
  const allCommands = getAllCommandsAboveTier(tier);

  // Find the most specific (longest) matching entry across all tiers
  let bestMatch = null;
  let bestLen = -1;
  for (const a of [...allowed, ...allCommands]) {
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
