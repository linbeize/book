import 'package:book/common/app_log.dart';
import 'package:book/data/repositories/source_repository.dart';
import 'package:book/source/import/source_importer.dart';
import 'package:book/source/model/book_source.dart';

/// 内置书源：让 App 开箱即用，无需手动导入。
///
/// 首次启动时把下方 [builtinSourcesJson] 写入本地书源库；已存在（按
/// bookSourceUrl 判重）则跳过，因此不会覆盖用户对书源的修改/启用状态。
///
/// 如需增删内置书源，直接改 [builtinSourcesJson] 即可——它与 App 里
/// 「导入书源」支持的格式完全一致（Legado JSON 数组）。
class BuiltinSources {
  BuiltinSources._();

  /// 内置书源定义（Legado 格式）。
  ///
  /// 该源对接自建小说站：搜索/详情/目录/正文全部走站点的只读 API，
  /// 规则使用纯 JSONPath，不依赖 JS，因此无需额外 jsLib。
  ///
  /// 若站点域名变化，改 [bookSourceUrl] 一处即可（其余均为相对路径）。
  static const String builtinSourcesJson = r'''
[
  {
    "bookSourceUrl": "http://novel.linbei.de",
    "bookSourceName": "爱看书（自建站）",
    "bookSourceGroup": "自建",
    "bookSourceType": 0,
    "enabled": true,
    "enabledExplore": true,
    "customOrder": 0,
    "weight": 0,
    "header": "",
    "searchUrl": "/api/search?kw={{key}}&size=30&p={{page}}",
    "exploreUrl": "",
    "jsLib": "",
    "ruleSearch": {
      "bookList": "$.data.list[*]",
      "name": "$.name",
      "author": "$.author",
      "kind": "$.cate_name",
      "wordCount": "$.text_num",
      "intro": "",
      "lastChapter": "$.chapter_title",
      "coverUrl": "$.cover",
      "bookUrl": "$.url"
    },
    "ruleBookInfo": {
      "init": "",
      "name": "$.data.novel.name",
      "author": "$.data.novel.author",
      "kind": "$.data.novel.cate_name",
      "wordCount": "$.data.novel.text_num",
      "intro": "$.data.novel.desc",
      "coverUrl": "$.data.novel.cover",
      "lastChapter": "$.data.novel.chapter_title",
      "tocUrl": "$.data.novel.toc_url",
      "canReName": ""
    },
    "ruleToc": {
      "chapterList": "$.data.list[*]",
      "chapterName": "$.title",
      "chapterUrl": "$.url",
      "isVolume": "",
      "updateTime": "$.updated_at",
      "nextTocUrl": "$.data.next_toc_url"
    },
    "ruleContent": {
      "content": "$.data.content",
      "nextContentUrl": "",
      "replaceRegex": "",
      "sourceRegex": "",
      "imageStyle": ""
    }
  }
]
''';

  /// 安装内置书源（幂等）。
  ///
  /// - 已存在同 bookSourceUrl 的源：跳过，不覆盖用户改动；
  /// - 解析失败或写库异常：仅记录日志，不影响 App 启动。
  static Future<void> ensureInstalled() async {
    try {
      final repo = SourceRepository.instance;

      final parsed = SourceImporter.parseJson(builtinSourcesJson);
      if (parsed.sources.isEmpty) {
        AppLog.w('BuiltinSources', '内置书源解析为空，跳过');
        return;
      }

      final toAdd = <BookSource>[];
      for (final s in parsed.sources) {
        final existing = await repo.getByUrl(s.bookSourceUrl);
        if (existing == null) {
          toAdd.add(s);
        }
      }

      if (toAdd.isEmpty) {
        AppLog.d('BuiltinSources', '内置书源已存在，无需安装');
        return;
      }

      await repo.upsertAll(toAdd);
      AppLog.i('BuiltinSources', '已安装内置书源 ${toAdd.length} 个');
    } catch (e, st) {
      // 内置书源安装失败不应阻断启动——用户仍可手动导入。
      AppLog.e('BuiltinSources', '安装内置书源失败', error: e, stackTrace: st);
    }
  }
}
