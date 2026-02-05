import 'dart:async';
import 'dart:io';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:uicons_pro/uicons_pro.dart';
import 'package:uuid/v4.dart';

import '../../core/app_logging.dart';
import '../../core/app_pref.dart';
import '../../core/const.dart';
import '../../data/database/db_activity.dart';
import '../../data/database/db_collection.dart';
import '../../data/database/db_profile.dart';
import '../../data/database/db_videos.dart';
import '../../data/models/activity_entity.dart';
import '../../data/models/collection_entity.dart';
import '../../data/models/library_entity.dart';
import '../../data/models/profile_entity.dart';
import '../../data/models/videos_entity.dart';
import '../../utils/helper.dart';
import 'home_panel/home_panel_library.dart';
import 'page_download/page_download_controller.dart';
import 'page_explore/page_explore_controller.dart';
import 'page_home/page_home_controller.dart';
import 'page_search/page_search_controller.dart';
import 'page_settings/page_settings_controller.dart';
import 'page_tools/page_tools_controller.dart';

class HomeController extends GetxController with StateMixin {
  final menus = <Map<String, dynamic>>[
    {'icon': UIconsPro.regularRounded.comet, 'name': kMenuHome},
    {'icon': UIconsPro.regularRounded.magnifying_glass_wave, 'name': kMenuSearch},
    {'icon': UIconsPro.regularRounded.book_alt, 'name': kMenuExplore},
    {'icon': UIconsPro.regularRounded.display_arrow_down, 'name': kMenuDownload},
    {'icon': UIconsPro.regularRounded.customization, 'name': kMenuTools},
    {'icon': UIconsPro.regularRounded.operating_system_upgrade, 'name': kMenuSetting},
  ];
  final currentMenuSelected = kMenuHome.obs;

  final loadingText = '...'.obs;
  final totalVideo = 0.obs;
  final footerText = ''.obs;
  final sideMenuWidth = 180.0.obs;

  // library
  final library = <Library>[].obs;
  final isDangerMode = false.obs;
  final isDropHovering = false.obs;

  // cart
  final cart = <Videos>[].obs;

  // profile
  final profile = Profile().obs;

  // playlist
  final playlist = <Collection>[].obs;

  

  @override
  Future<void> onInit() async {
    super.onInit();
    
    change(200, status: RxStatus.loading());
    AppLog.logI('root home ==> onInit called');

    cart.value = AppPref.getAppCart();
    ever<List<Videos>>(cart, (value) => AppPref.setAppCart(value));

    profile.value = await DBProfile.getProfile() ?? Profile();

    totalVideo.value = await DBVideos.getCount();
    final _totalFileSize = await DBVideos.getTotalFileSizeAllVideo() ?? 0;
    footerText.value = 'Iddle | Total Video: ${totalVideo.value} (${_totalFileSize.toFileSizeFormat()})';

    sideMenuWidth.value = AppPref.getAppHideSideMenu() ? 65 : 180;

    await DBActivity.getCountRelapseToday();
    isDangerMode.value = await DBActivity.getCountRelapseToday() >= AppPref.getAppMaxColi();

    await getAllPlaylist();

    change(200, status: RxStatus.success());
  }

  Future<void> onRefreshAllContent() async {
    try {
      final sw = Stopwatch()..start();
      footerText.value = 'Refreshing...';

      await Get.find<PageHomeController>().onRefresh();
      await Get.find<PageSearchController>().onRefresh();
      await Get.find<PageExploreController>().onRefresh();
      await Get.find<PageDownloadController>().onRefresh();
      await Get.find<PageToolsController>().onRefresh();
      await Get.find<PageSettingsController>().onRefresh();

      await DBActivity.getCountRelapseToday();
      isDangerMode.value = await DBActivity.getCountRelapseToday() >= AppPref.getAppMaxColi();

      final _totalFileSize = await DBVideos.getTotalFileSizeAllVideo() ?? 0;
      totalVideo.value = await DBVideos.getCount();
      footerText.value = 'Iddle | Total Video: ${totalVideo.value} (${_totalFileSize.toFileSizeFormat()})';

      AppLog.logS('Refresh All Content Take Time: ${sw.elapsedMilliseconds} ms');
      change(200, status: RxStatus.success());
    } catch (e) {
      ExAlert.adaptive(
        title: Text('Ups'),
        content: Text('${e.toString()}'),
        actions: [
          CupertinoDialogAction(
            child: Text('Refresh', style: TextStyle(color: Vx.red500, fontSize: 13)),
            onPressed: () async {
              await onRefreshAllContent();
              Get.back();
            },
          ),
        ],
      );
    }
  }

  Future<void> onMenuChange(String menu) async {
    currentMenuSelected.value = menu;
  }


  // ──────────────────────────────────────────────────────────────
  // onDropEvent
  // ──────────────────────────────────────────────────────────────
  void onDropEnter(DropEvent event) => isDropHovering.value = true;
  void onDropLeave(DropEvent event) => isDropHovering.value = false;
  void onDropEnded(DropEvent event) => isDropHovering.value = false;

  Future<void> onDropEvent(PerformDropEvent event) async {
    isDropHovering.value = false;

    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null) continue;

      reader.getValue<Uri>(Formats.fileUri, (data) async {
        if (data == null) return;
        final path = data.path;

        // folder drop -> add library
        final isFolder = await FileSystemEntity.isDirectory(path);
        if (isFolder) {
          final _path = path.removeLast(1)!;

          final newLibrary = await HelperFilePicker.scanFolderAndSubFolder(_path);
          newLibrary?.alias = newLibrary.rootFolder?.getLastPath();

          await HomePanelLibrary.showDialogAddorEditLibrary(library: newLibrary, isFromDrop: true);
          return;
        }

        // video drop -> play
        if (path.toLowerCase().endsWith('.mp4')) {
          await _openDroppedVideo(path);
        } else {
          await HelperToast.warn('File not supported');
        }
      });
    }
  }

  Future<void> _openDroppedVideo(String path) async {
    final decodedPath = Uri.parse(path).toFilePath();
    final file = File(decodedPath);
    if (!file.existsSync()) {
      await HelperToast.warn('File not found');
      return;
    }

    final fileName = decodedPath.getLastPath();
    final cleanTitle = fileName.contains('.') ? fileName.split('.').first : fileName;

    final video = Videos(
      id: UuidV4().generate(),
      videoPath: decodedPath,
      videoCode: decodedPath.getVideoCode(),
      title: cleanTitle,
      viewCount: 0,
      filesize: await file.length(),
      createdAt: DateTime.now().toStringEx(),
      updatedAt: DateTime.now().toStringEx(),
    );

    await HelperOpener.openVideoFile(video);
  }

  // ────────────────────────────────────────────────────────────────
  // ⵌ profile
  // ────────────────────────────────────────────────────────────────
  Future<void> onOpenProfile() async {
    final tfName = TextEditingController(text: profile.value.name);
    final fnName = FocusNode();
    
    // profile 
    profile.value = await DBProfile.getProfile() ?? Profile();

    // relapse
    final relapse = <Activity>[].obs;
    final countWeek = 0.obs;
    final countMonth = 0.obs;
    final countAll = 0.obs;

    relapse.value = await DBActivity.getAllRelapse();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final startOfMonth = DateTime(today.year, today.month, 1);

    var weekTotal = 0;
    var monthTotal = 0;
    var allTotal = 0;

    for (final item in relapse) {
      final rawDate = item.content;
      if (rawDate.isNullOrEmpty) continue;
      final date = rawDate!.toDateEx(format: kYMd);
      final times = item.times ?? 1;

      allTotal += times;
      if (!date.isBefore(startOfWeek)) {
        weekTotal += times;
      }
      if (!date.isBefore(startOfMonth)) {
        monthTotal += times;
      }
    }

    countWeek.value = weekTotal;
    countMonth.value = monthTotal;
    countAll.value = allTotal;

    ExAlert.adaptive(
      title: HStack(
        [
          Text(
            'ⵌ Edit Profile',
            style: TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.left,
            overflow: TextOverflow.ellipsis,
          ).expand(),
          ExCloseButton(),
        ],
      ).pOnly(bottom: 16),
      content: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 90),
        child: VStack(
          [
            CupertinoTextField(
              controller: tfName,
              focusNode: fnName,
              placeholder: 'Your Name',
              placeholderStyle: TextStyle(fontSize: 13, color: Vx.neutral500),
              prefix: Icon(UIconsPro.regularRounded.user, size: 14).pOnly(left: 8),
              style: TextStyle(fontSize: 13, color: Vx.white),
              onSubmitted: (value) async => await _editProfile(value),
            ).pOnly(bottom: 16),
            
            Text('• First Open App: ${profile.value.createdAt?.reformatDate(from: kFull, to: kMdY)}').pOnly(bottom: 4),
            Text('• Total Relapse: ${countAll.value} Times').pOnly(bottom: 4),
            Text('• Watch Time: ${Duration(seconds: profile.value.totalWatchDuration ?? 0).inMinutes} Minutes', ).pOnly(bottom: 4),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: Text('Save', style: TextStyle(fontSize: 13)),
          onPressed: () async {
            await _editProfile(tfName.text);
          },
        ),
      ],
    );
  }

  Future<void> _editProfile(String newName) async {
    final _newProfile = profile.value;
    _newProfile.name = newName;
    await DBProfile.update(_newProfile);
    profile.value = await DBProfile.getProfile() ?? Profile();
    await HelperToast.success('Saved');
    Get.back();
  }



  // ────────────────────────────────────────────────────────────────
  // ⵌ playlist
  // ────────────────────────────────────────────────────────────────
  Future<void> getAllPlaylist() async {
    playlist.clear();
    playlist.value = await DBCollection.getAllPlaylist();
  }

}

// ────────────────────────────────────────────────────────────────
// # menu const
// ────────────────────────────────────────────────────────────────
const kMenuHome = 'Home';
const kMenuSearch = 'Search';
const kMenuExplore = 'Explore';
const kMenuDownload = 'Download';
const kMenuTools = 'Tools';
const kMenuSetting = 'Settings';
