import 'dart:html' as html;
import 'package:flutter/material.dart';

enum AppLanguage { en, zhHans, zhHant }

const _languageStorageKey = 'trinity_app_language';

AppLanguage loadAppLanguage() {
  switch (html.window.localStorage[_languageStorageKey]) {
    case 'zh-Hans':
      return AppLanguage.zhHans;
    case 'zh-Hant':
      return AppLanguage.zhHant;
    case 'en':
    default:
      return AppLanguage.en;
  }
}

void saveAppLanguage(AppLanguage language) {
  switch (language) {
    case AppLanguage.en:
      html.window.localStorage[_languageStorageKey] = 'en';
      break;
    case AppLanguage.zhHans:
      html.window.localStorage[_languageStorageKey] = 'zh-Hans';
      break;
    case AppLanguage.zhHant:
      html.window.localStorage[_languageStorageKey] = 'zh-Hant';
      break;
  }
}

Locale appLanguageToLocale(AppLanguage language) {
  switch (language) {
    case AppLanguage.en:
      return const Locale('en');
    case AppLanguage.zhHans:
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
    case AppLanguage.zhHant:
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
  }
}

String appLanguageLabel(AppLanguage language) {
  switch (language) {
    case AppLanguage.en:
      return 'English';
    case AppLanguage.zhHans:
      return '中文(简体)';
    case AppLanguage.zhHant:
      return '中文(繁體)';
  }
}

String tr(AppLanguage language, String key) {
  const strings = {
    'memory': {
      'en': 'memory',
      'zh-Hans': '记忆',
      'zh-Hant': '記憶',
    },
    'setup': {
      'en': 'setup',
      'zh-Hans': '设置',
      'zh-Hant': '設置',
    },
    'skills': {
      'en': 'skills',
      'zh-Hans': '技能',
      'zh-Hant': '技能',
    },
    'automations': {
      'en': 'automations',
      'zh-Hans': '自动化',
      'zh-Hant': '自動化',
    },
    'crons': {
      'en': 'crons',
      'zh-Hans': '定时任务',
      'zh-Hant': '定時任務',
    },
    'hooks': {
      'en': 'hooks',
      'zh-Hans': '钩子',
      'zh-Hant': '鉤子',
    },
    'webhooks': {
      'en': 'webhooks',
      'zh-Hans': '网络钩子',
      'zh-Hant': '網路鉤子',
    },
    'polls': {
      'en': 'polls',
      'zh-Hans': '投票',
      'zh-Hant': '投票',
    },
    'settings': {
      'en': 'settings',
      'zh-Hans': '设置',
      'zh-Hant': '設定',
    },
    'close': {
      'en': 'close',
      'zh-Hans': '关闭',
      'zh-Hant': '關閉',
    },
    'theme': {
      'en': 'theme',
      'zh-Hans': '主题',
      'zh-Hant': '主題',
    },
    'font': {
      'en': 'font',
      'zh-Hans': '字体',
      'zh-Hant': '字體',
    },
    'language': {
      'en': 'language',
      'zh-Hans': '语言',
      'zh-Hant': '語言',
    },
    'system': {
      'en': 'system',
      'zh-Hans': '跟随系统',
      'zh-Hant': '跟隨系統',
    },
    'dark': {
      'en': 'dark',
      'zh-Hans': '深色',
      'zh-Hant': '深色',
    },
    'light': {
      'en': 'light',
      'zh-Hans': '浅色',
      'zh-Hant': '淺色',
    },
    'search': {
      'en': 'search',
      'zh-Hans': '搜索',
      'zh-Hant': '搜尋',
    },
    'similarity': {
      'en': 'similarity',
      'zh-Hans': '相似度',
      'zh-Hant': '相似度',
    },
    'admin': {
      'en': 'admin',
      'zh-Hans': '管理',
      'zh-Hant': '管理',
    },
    'users': {
      'en': 'users',
      'zh-Hans': '用户',
      'zh-Hant': '用戶',
    },
    'audit': {
      'en': 'audit',
      'zh-Hans': '审计',
      'zh-Hant': '稽核',
    },
    'health': {
      'en': 'health',
      'zh-Hans': '健康',
      'zh-Hant': '健康',
    },
    'rbac': {
      'en': 'rbac',
      'zh-Hans': '权限',
      'zh-Hant': '權限',
    },
    'sessions': {
      'en': 'sessions',
      'zh-Hans': '会话',
      'zh-Hant': '會話',
    },
    'channels': {
      'en': 'channels',
      'zh-Hans': '频道',
      'zh-Hant': '頻道',
    },
    'env': {
      'en': 'env',
      'zh-Hans': '环境变量',
      'zh-Hant': '環境變數',
    },
    'copilot': {
      'en': 'copilot',
      'zh-Hans': '副驾',
      'zh-Hant': '副駕',
    },
    'schedule_simple': {
      'en': 'simple',
      'zh-Hans': '简易',
      'zh-Hant': '簡易',
    },
    'schedule_cron': {
      'en': 'cron',
      'zh-Hans': '表达式',
      'zh-Hant': '表達式',
    },
    'frequency': {
      'en': 'frequency',
      'zh-Hans': '频率',
      'zh-Hant': '頻率',
    },
    'sessions_label': {
      'en': 'sessions',
      'zh-Hans': '会话列表',
      'zh-Hant': '會話列表',
    },
    'new_session': {
      'en': 'new session',
      'zh-Hans': '新会话',
      'zh-Hant': '新會話',
    },
    'main_session': {
      'en': 'main',
      'zh-Hans': '主会话',
      'zh-Hant': '主會話',
    },
    'command_palette': {
      'en': 'command palette',
      'zh-Hans': '命令面板',
      'zh-Hant': '命令面板',
    },
    'type_command': {
      'en': 'type a command...',
      'zh-Hans': '输入命令...',
      'zh-Hant': '輸入命令...',
    },
    'notifications': {
      'en': 'notifications',
      'zh-Hans': '通知',
      'zh-Hant': '通知',
    },
    'no_notifications': {
      'en': 'no notifications',
      'zh-Hans': '暂无通知',
      'zh-Hant': '暫無通知',
    },
    'clear_all': {
      'en': 'clear all',
      'zh-Hans': '清除全部',
      'zh-Hant': '清除全部',
    },
    'templates': {
      'en': 'templates',
      'zh-Hans': '模板',
      'zh-Hant': '範本',
    },
    'save_template': {
      'en': 'save as template',
      'zh-Hans': '保存为模板',
      'zh-Hant': '儲存為範本',
    },
    'attach_file': {
      'en': 'attach file',
      'zh-Hans': '附加文件',
      'zh-Hant': '附加檔案',
    },
    'export_canvas': {
      'en': 'export',
      'zh-Hans': '导出',
      'zh-Hant': '匯出',
    },
    'copy_image': {
      'en': 'copy as image',
      'zh-Hans': '复制为图片',
      'zh-Hant': '複製為圖片',
    },
    'download_png': {
      'en': 'download PNG',
      'zh-Hans': '下载PNG',
      'zh-Hant': '下載PNG',
    },
    'download_json': {
      'en': 'download JSON',
      'zh-Hans': '下载JSON',
      'zh-Hant': '下載JSON',
    },
    'sso_login': {
      'en': 'sign in with SSO',
      'zh-Hans': '使用SSO登录',
      'zh-Hant': '使用SSO登入',
    },
  };

  final langKey = switch (language) {
    AppLanguage.en => 'en',
    AppLanguage.zhHans => 'zh-Hans',
    AppLanguage.zhHant => 'zh-Hant',
  };
  return strings[key]?[langKey] ?? strings[key]?['en'] ?? key;
}
