/**
 * i18n translations — 1:1 port of core/i18n.dart
 *
 * ~50 translation keys, 3 locales: en, zh-Hans, zh-Hant
 */

export type AppLanguage = 'en' | 'zh-Hans' | 'zh-Hant';

export const languageLabels: Record<AppLanguage, string> = {
  en: 'English',
  'zh-Hans': '中文(简体)',
  'zh-Hant': '中文(繁體)',
};

const translations: Record<string, Record<AppLanguage, string>> = {
  memory: { en: 'memory', 'zh-Hans': '记忆', 'zh-Hant': '記憶' },
  setup: { en: 'setup', 'zh-Hans': '设置向导', 'zh-Hant': '設置嚮導' },
  skills: { en: 'skills', 'zh-Hans': '技能', 'zh-Hant': '技能' },
  settings: { en: 'settings', 'zh-Hans': '设置', 'zh-Hant': '設定' },
  command_palette: { en: 'command palette', 'zh-Hans': '命令面板', 'zh-Hant': '命令面板' },
  admin: { en: 'admin', 'zh-Hans': '管理', 'zh-Hant': '管理' },
  sessions: { en: 'sessions', 'zh-Hans': '会话', 'zh-Hant': '會話' },
  knowledge: { en: 'knowledge', 'zh-Hans': '知识库', 'zh-Hant': '知識庫' },
  automations: { en: 'automations', 'zh-Hans': '自动化', 'zh-Hant': '自動化' },
  channels: { en: 'channels', 'zh-Hans': '频道', 'zh-Hant': '頻道' },
  notifications: { en: 'notifications', 'zh-Hans': '通知', 'zh-Hant': '通知' },
  agents: { en: 'agents', 'zh-Hans': '代理', 'zh-Hant': '代理' },
  login: { en: 'login', 'zh-Hans': '登录', 'zh-Hant': '登錄' },
  sign_up: { en: 'sign up', 'zh-Hans': '注册', 'zh-Hant': '註冊' },
  logout: { en: 'logout', 'zh-Hans': '退出', 'zh-Hant': '登出' },
  email: { en: 'email', 'zh-Hans': '邮箱', 'zh-Hant': '電子郵件' },
  password: { en: 'password', 'zh-Hans': '密码', 'zh-Hant': '密碼' },
  remember_email: { en: 'remember email', 'zh-Hans': '记住邮箱', 'zh-Hant': '記住郵箱' },
  sso_login: { en: 'SSO login', 'zh-Hans': 'SSO 登录', 'zh-Hant': 'SSO 登錄' },
  guest_access: { en: 'guest access', 'zh-Hans': '访客访问', 'zh-Hant': '訪客訪問' },
  start_conversation: { en: 'start a conversation', 'zh-Hans': '开始对话', 'zh-Hant': '開始對話' },
  send: { en: 'send', 'zh-Hans': '发送', 'zh-Hant': '發送' },
  cancel: { en: 'cancel', 'zh-Hans': '取消', 'zh-Hant': '取消' },
  save: { en: 'save', 'zh-Hans': '保存', 'zh-Hant': '儲存' },
  delete: { en: 'delete', 'zh-Hans': '删除', 'zh-Hant': '刪除' },
  close: { en: 'close', 'zh-Hans': '关闭', 'zh-Hant': '關閉' },
  loading: { en: 'loading...', 'zh-Hans': '加载中...', 'zh-Hant': '載入中...' },
  error: { en: 'error', 'zh-Hans': '错误', 'zh-Hant': '錯誤' },
  theme: { en: 'theme', 'zh-Hans': '主题', 'zh-Hant': '主題' },
  language: { en: 'language', 'zh-Hans': '语言', 'zh-Hant': '語言' },
  font: { en: 'font', 'zh-Hans': '字体', 'zh-Hant': '字體' },
  account: { en: 'account', 'zh-Hans': '账户', 'zh-Hant': '帳戶' },
  users: { en: 'users', 'zh-Hans': '用户', 'zh-Hant': '用戶' },
  audit: { en: 'audit', 'zh-Hans': '审计', 'zh-Hant': '審計' },
  health: { en: 'health', 'zh-Hans': '健康', 'zh-Hant': '健康' },
  rbac: { en: 'rbac', 'zh-Hans': '权限管理', 'zh-Hant': '權限管理' },
  openclaws: { en: 'openclaws', 'zh-Hans': 'OpenClaw 实例', 'zh-Hant': 'OpenClaw 實例' },
  environment: { en: 'environment', 'zh-Hans': '环境变量', 'zh-Hant': '環境變數' },
  copilot: { en: 'copilot', 'zh-Hans': '助手', 'zh-Hant': '助手' },
  approve: { en: 'approve', 'zh-Hans': '批准', 'zh-Hant': '批准' },
  reject: { en: 'reject', 'zh-Hans': '拒绝', 'zh-Hant': '拒絕' },
  no_pending_approvals: { en: 'no pending approvals', 'zh-Hans': '没有待处理的审批', 'zh-Hant': '沒有待處理的審批' },
  prompt_templates: { en: 'prompt templates', 'zh-Hans': '提示词模板', 'zh-Hant': '提示詞模板' },
  new_session: { en: 'new session', 'zh-Hans': '新会话', 'zh-Hant': '新會話' },
  main: { en: 'main', 'zh-Hans': '主会话', 'zh-Hant': '主會話' },
  crons: { en: 'crons', 'zh-Hans': '定时任务', 'zh-Hant': '定時任務' },
  hooks: { en: 'hooks', 'zh-Hans': '钩子', 'zh-Hant': '鉤子' },
  webhooks: { en: 'webhooks', 'zh-Hans': '网络钩子', 'zh-Hant': '網路鉤子' },
  polls: { en: 'polls', 'zh-Hans': '投票', 'zh-Hant': '投票' },
};

/**
 * Translate a key into the specified language. Falls back to English, then the raw key.
 */
export function tr(language: AppLanguage, key: string): string {
  const entry = translations[key];
  if (!entry) return key;
  return entry[language] ?? entry.en ?? key;
}
