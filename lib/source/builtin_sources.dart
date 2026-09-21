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
    "exploreUrl": "热门榜单::/api/rank\n玄幻魔法::/api/books?cate=1&ot=1\n武侠修真::/api/books?cate=2&ot=1\n都市言情::/api/books?cate=3&ot=1\n历史军事::/api/books?cate=4&ot=1\n侦探推理::/api/books?cate=5&ot=1\n网游动漫::/api/books?cate=6&ot=1\n科幻灵异::/api/books?cate=7&ot=1\n高干总裁::/api/books?cate=11&ot=1\n其他类型::/api/books?cate=13&ot=1\n最近更新::/api/books?ot=2\n字数最多::/api/books?ot=3",
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
    "ruleExplore": {
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

      // 诊断：把关键状态写入日志缓冲（「我的」-「日志」可查看）。
      // 上线版本无控制台输出，此处是排查书源问题的主要途径。
      AppLog.i('BuiltinSources', '开始检查内置书源');

      final parsed = SourceImporter.parseJson(builtinSourcesJson);
      AppLog.i('BuiltinSources',
          '解析结果: ${parsed.count} 个, 跳过 ${parsed.skipped}');
      if (parsed.sources.isEmpty) {
        AppLog.w('BuiltinSources', '内置书源解析为空，跳过');
        return;
      }

      for (final s in parsed.sources) {
        AppLog.i('BuiltinSources',
            '候选: ${s.bookSourceName} url=${s.bookSourceUrl} '
            'searchUrl=${s.searchUrl} enabled=${s.enabled}');
      }

      final total = await repo.count();
      final toAdd = <BookSource>[];
      for (final s in parsed.sources) {
        final existing = await repo.getByUrl(s.bookSourceUrl);
        if (existing == null) {
          toAdd.add(s);
        } else {
          AppLog.i('BuiltinSources', '已存在，跳过: ${s.bookSourceUrl}');
        }
      }

      if (toAdd.isEmpty) {
        AppLog.i('BuiltinSources', '内置书源已存在，无需安装（库中共 $total 条）');
        return;
      }

      await repo.upsertAll(toAdd);

      // 安装后回读校验：确认规则确实写入了（而非只写了 meta）。
      for (final s in toAdd) {
        final back = await repo.getByUrl(s.bookSourceUrl);
        if (back == null) {
          AppLog.e('BuiltinSources', '写入后读回失败: ${s.bookSourceUrl}');
          continue;
        }
        AppLog.i('BuiltinSources',
            '写入成功: ${back.bookSourceName} enabled=${back.enabled} '
            'searchUrl=${back.searchUrl} '
            'bookList=${back.ruleSearch.bookList} '
            'tocList=${back.ruleToc.chapterList} '
            'content=${back.ruleContent.content}');
      }

      final after = await repo.count();
      AppLog.i('BuiltinSources', '已安装内置书源 ${toAdd.length} 个（库中共 $after 条）');
    } catch (e, st) {
      // 内置书源安装失败不应阻断启动——用户仍可手动导入。
      AppLog.e('BuiltinSources', '安装内置书源失败', error: e, stackTrace: st);
    }
  }
}
