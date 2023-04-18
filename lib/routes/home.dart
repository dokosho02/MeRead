import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/post_container.dart';
import '../../utils/db.dart';
import '../utils/parse.dart';
import '../../utils/key.dart';
import '../../routes/feed/add_feed.dart';
import '../../routes/feed/feed.dart';
import '../../routes/read.dart';
import '../../routes/setting/set.dart';
import '../../models/models.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  Map<String, List<Feed>> feedListGroupByCategory = {};
  List<Post> postList = [];
  bool onlyUnread = false;
  bool onlyFavorite = false;
  Map<String, dynamic> readPageInitData = {};
  Map<int, int> unreadCount = {};

  Future<void> getFeedList() async {
    await feedsGroupByCategory().then(
      (value) => setState(
        () {
          feedListGroupByCategory = value;
        },
      ),
    );
  }

  Future<void> getPostList() async {
    await posts().then(
      (value) => setState(
        () {
          postList = value;
        },
      ),
    );
  }

  Future<void> getUnreadPost() async {
    await unreadPosts().then(
      (value) => setState(
        () {
          postList = value;
        },
      ),
    );
  }

  Future<void> getFavoritePost() async {
    await favoritePosts().then(
      (value) => setState(
        () {
          postList = value;
        },
      ),
    );
  }

  Future<void> getReadPageInitData() async {
    await getAllReadPageInitData().then(
      (value) => setState(
        () {
          readPageInitData = value;
        },
      ),
    );
  }

  Future<void> getUnreadCount() async {
    await unreadPostCount().then(
      (value) => setState(
        () {
          unreadCount = value;
        },
      ),
    );
  }

  Future<void> refresh() async {
    List<Feed> feedList = await feeds();
    // int failCount = 0;
    List<Feed> failedFeedList = [];
    await Future.wait(
      feedList.map(
        (e) => parseFeedContent(e).then(
          (value) async {
            if (value) {
              if (onlyUnread) {
                await getUnreadPost();
              } else if (!onlyFavorite) {
                await getPostList();
              }
              await getUnreadCount();
            } else {
              // failCount++;
              failedFeedList.add(e);
            }
          },
        ),
      ),
    );
    int failCount = failedFeedList.length;
    if (failCount > 0) {
      if (!mounted) return;

      String failedFeedListStr = '';
      failedFeedList.map(
        (e) => failedFeedListStr += e.name + "\n"
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('更新失败 $failCount 个订阅源\n$failedFeedListStr'),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('更新成功'),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          duration: Duration(seconds: 2),
        ),
      );
    }
    // 保证订阅源的文章数不大于 feedMaxSaveCount
    final int feedMaxSaveCount = await getFeedMaxSaveCount();
    checkPostCount(feedMaxSaveCount);
  }

  @override
  void initState() {
    super.initState();
    getFeedList();
    getPostList();
    getUnreadCount();
    getReadPageInitData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('悦读'),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () async {
              if (onlyUnread) {
                await getPostList();
                setState(() {
                  onlyUnread = false;
                });
              } else {
                await getUnreadPost();
                setState(() {
                  onlyUnread = true;
                  onlyFavorite = false;
                });
              }
            },
            icon: onlyUnread
                ? const Icon(Icons.radio_button_checked)
                : const Icon(Icons.radio_button_unchecked),
          ),
          IconButton(
            onPressed: () async {
              if (onlyFavorite) {
                await getPostList();
                setState(() {
                  onlyFavorite = false;
                });
              } else {
                await getFavoritePost();
                setState(() {
                  onlyFavorite = true;
                  onlyUnread = false;
                });
              }
            },
            icon: onlyFavorite
                ? const Icon(Icons.bookmark)
                : const Icon(Icons.bookmark_border_outlined),
          ),
          PopupMenuButton(
            position: PopupMenuPosition.under,
            itemBuilder: (BuildContext context) {
              return <PopupMenuEntry>[
                PopupMenuItem(
                  onTap: () async {
                    await markAllPostsAsRead();
                    if (onlyUnread) {
                      getUnreadPost();
                    } else if (onlyFavorite) {
                      getFavoritePost();
                    } else {
                      getPostList();
                    }
                    getUnreadCount();
                  },
                  child: const Text('全标已读'),
                ),
                PopupMenuItem(
                  onTap: () {
                    // 打开订阅源添加页面，返回时刷新订阅源列表
                    Future.delayed(const Duration(seconds: 0), () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (context) => const AddFeedPage(),
                        ),
                      ).then((value) => getFeedList());
                    });
                  },
                  child: const Text('添加订阅'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  onTap: () {
                    Future.delayed(const Duration(seconds: 0), () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (context) => const SetPage(),
                        ),
                      ).then((value) {
                        getFeedList();
                        if (onlyUnread) {
                          getUnreadPost();
                        } else if (onlyFavorite) {
                          getFavoritePost();
                        } else {
                          getPostList();
                        }
                        getReadPageInitData();
                      });
                    });
                  },
                  child: const Text('设置'),
                ),
              ];
            },
          ),
        ],
      ),
      drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.4,
      drawer: Drawer(
        child: SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 12, bottom: 12),
            itemCount: feedListGroupByCategory.length,
            itemBuilder: (BuildContext context, int index) {
              return ExpansionTile(
                title: Text(
                  feedListGroupByCategory.keys.toList()[index],
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                children: [
                  Column(
                    children: [
                      for (Feed feed
                          in feedListGroupByCategory.values.toList()[index])
                        ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.fromLTRB(40, 0, 20, 0),
                          title: Text(
                            feed.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            unreadCount[feed.id] == null
                                ? ''
                                : unreadCount[feed.id].toString(),
                          ),
                          onTap: () {
                            if (!mounted) return;
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (context) => FeedPage(feed: feed),
                              ),
                            ).then((value) {
                              getFeedList();
                              getUnreadCount();
                              if (onlyUnread) {
                                getUnreadPost();
                              } else if (onlyFavorite) {
                                getFavoritePost();
                              } else {
                                getPostList();
                              }
                            });
                          },
                        ),
                    ],
                  )
                ],
              );
            },
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView.separated(
          cacheExtent: 30, // 预加载
          itemCount: postList.length,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          itemBuilder: (context, index) {
            return GestureDetector(
              // 根据 openType 打开文章
              onTap: () async {
                if (postList[index].openType == 2) {
                  // 系统浏览器打开
                  await launchUrl(
                    Uri.parse(postList[index].link),
                    mode: LaunchMode.externalApplication,
                  );
                } else {
                  // 应用内打开：阅读器 or 标签页
                  final bool fullText =
                      await feedFullText(postList[index].feedId) == 1;
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (context) => ReadPage(
                        post: postList[index],
                        initData: readPageInitData,
                        fullText: fullText,
                      ),
                    ),
                  ).then((value) {
                    // 返回时刷新文章列表
                    if (onlyUnread) {
                      getUnreadPost();
                    } else if (onlyFavorite) {
                      getFavoritePost();
                    } else {
                      getPostList();
                    }
                    getUnreadCount();
                  });
                }
                // 标记文章为已读
                if (postList[index].read == 0) {
                  markPostAsRead(postList[index].id!);
                }
              },
              child: PostContainer(post: postList[index]),
            );
          },
          separatorBuilder: (context, index) {
            return const SizedBox(height: 4);
          },
        ),
      ),
    );
  }
}
