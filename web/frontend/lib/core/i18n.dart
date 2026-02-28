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
  };

  final langKey = switch (language) {
    AppLanguage.en => 'en',
    AppLanguage.zhHans => 'zh-Hans',
    AppLanguage.zhHant => 'zh-Hant',
  };
  return strings[key]?[langKey] ?? strings[key]?['en'] ?? key;
}
