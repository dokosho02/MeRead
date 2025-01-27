import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:opml/opml.dart';
import 'package:webfeed/webfeed.dart';
import 'package:http/http.dart';

import '../utils/db.dart';
import '../models/models.dart';

// 解析订阅源
// 参数：订阅源地址
// 返回：Feed 对象
// 注意：同时考虑 RSS 和 Atom 格式
Future<Feed?> parseFeed(String url,
    [String? categoryName, String? feedName]) async {
  categoryName ??= '默认分类';
  int defaultOpenType = 0;
  try {
    final response = await get(Uri.parse(url));
    final postXmlString = utf8.decode(response.bodyBytes);
    try {
      RssFeed rssFeed = RssFeed.parse(postXmlString);
      feedName ??= rssFeed.title;
      return Feed(
        name: feedName!,
        url: url,
        description: rssFeed.description?? "",
        category: categoryName,
        fullText: 0,
        openType: defaultOpenType,
      );
    } catch (e) {
      AtomFeed atomFeed = AtomFeed.parse(postXmlString);
      return Feed(
        name: atomFeed.title!,
        url: url,
        description: atomFeed.subtitle ?? "",
        category: categoryName,
        fullText: 0,
        openType: defaultOpenType,
      );
    }
  } catch (e) {
    return null;
  }
}

// 解析订阅源内容，得到 Post，存入数据库，成功返回 true，失败返回 false
// 参数：订阅源地址
// 返回：是否成功
// 注意：如果 Post 已存在，则不存入数据库
Future<bool> parseFeedContent(Feed feed) async {
  try {
    final response = await get(Uri.parse(feed.url));
    final postXmlString = utf8.decode(response.bodyBytes);
    final String? feedLastUpdated = await getFeedLatestPostPubDate(feed.id!);
    try {
      RssFeed rssFeed = RssFeed.parse(postXmlString);
      List<Future> futures = [];
      for (RssItem item in rssFeed.items!) {
        if (feedLastUpdated == item.pubDate.toString()) {
          break;
        }
        futures.add(parseRSSPostFuturesItem(item, feed));
      }
      await Future.wait(futures);
      return true;
    } catch (e) {
      AtomFeed atomFeed = AtomFeed.parse(postXmlString);
      List<Future> futures = [];
      for (AtomItem item in atomFeed.items!) {
        if (feedLastUpdated == item.updated.toString()) {
          break;
        }
        futures.add(parseAtomPostFuturesItem(item, feed));
      }
      await Future.wait(futures);
      return true;
    }
  } catch (e) {
    return false;
  }
}

Future<void> parseRSSPostFuturesItem(RssItem item, Feed feed) async {
  String title = item.title!.trim();
  
  var descLen = item.description?.length ?? 0;
  var contentLen = item.content?.value.length ?? 0;
  var contentOrDesc = descLen > contentLen ? item.description : item.content?.value;
  
  Post post = Post(
    title: title,
    feedId: feed.id!,
    feedName: feed.name,
    link: item.link!,
    content: contentOrDesc!,
    pubDate: item.pubDate!.toString(),
    read: 0,
    favorite: 0,
    openType: feed.openType,
  );
  await insertPost(post);
}

Future<void> parseAtomPostFuturesItem(AtomItem item, Feed feed) async {
  var summaryLen = item.summary?.length ?? 0;
  var contentLen = item.content?.length ?? 0;
  var contentOrSumm = summaryLen > contentLen ? item.summary : item.content;
  Post post = Post(
    title: item.title!,
    feedId: feed.id!,
    feedName: feed.name,
    link: item.links![0].href!,
    content: contentOrSumm!,
    pubDate: item.updated!.toString(),
    read: 0,
    favorite: 0,
    openType: feed.openType,
  );
  await insertPost(post);
}

// 解析 OPML 文件
Future<int> parseOpml(FilePickerResult result) async {
  final file = result.files.first;
  // 读取文件内容，转为字符串
  final File opmlFile = File(file.path!);
  final String opmlString = await opmlFile.readAsString();
  int failCount = 0;
  final opml = OpmlDocument.parse(opmlString);
  await Future.wait(
    opml.body.map(
      (category) async {
        final String? categoryName = category.title;
        await Future.wait(
          category.children!.map(
            (feed) async {
              if (!await feedExist(feed.xmlUrl!)) {
                Feed? feedObj =
                    await parseFeed(feed.xmlUrl!, categoryName, feed.title!);
                if (feedObj != null) {
                  await insertFeed(feedObj);
                } else {
                  failCount++;
                }
              }
            },
          ),
        );
      },
    ),
  );
  return failCount;
}

// 导出 OPML 文件
Future<String> exportOpml() async {
  final head = OpmlHeadBuilder().title('Feeds From 悦读 App').build();
  final body = <OpmlOutline>[];
  final Map<String, List<Feed>> feedMap = await feedsGroupByCategory();
  for (var category in feedMap.keys) {
    var c = OpmlOutlineBuilder().title(category).text(category);
    for (var feed in feedMap[category]!) {
      c.addChild(OpmlOutlineBuilder()
          .title(feed.name)
          .text(feed.name)
          .type('rss')
          .xmlUrl(feed.url)
          .build());
    }
    body.add(c.build());
  }
  final opml = OpmlDocument(
    head: head,
    body: body,
  );
  return opml.toXmlString(pretty: true);
}
