import 'dart:async';

import 'package:ex_kit/ex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';

import '../../../core/app_logging.dart';
import '../../../data/api/api_javit.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_loading.dart';
import '../../../utils/helper_toast.dart';

class PageSearchController extends GetxController {
  final tecSearch = TextEditingController();
  final isSearchMode = false.obs;
  final fnSearch = FocusNode();
  final phSearch = ''.obs;

  final scrollGridController = ScrollController();
  final scrollListController = ScrollController();

  final viewModeSelected = kGrid.obs; // grid | list
  final videos = <Videos>[].obs;
  final isFresh = true.obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    AppLog.logI('page search ==> onInit called');
    viewModeSelected.value = kGrid;
    isFresh.value = await DBVideos.getCount() == 0;
    phSearch.value = 'Video Code or Title or Path...'; // await DBVideos.getRandomVideoCode();
    await onReset();
    videos.shuffle();

  }

  Future<void> renewMetadata(Videos videos) async {
    await Overlayment.dismissLast();
    HelperLoading.show();
    await ApiJavit.getMetadata(code: videos.videoCode ?? '').then((resp) {
      HelperLoading.dismiss();
      final newVideos = videos;
      newVideos.title = resp.title;
      newVideos.titleJa = resp.titleJa;

      newVideos.description = resp.description;
      newVideos.fanArt = resp.fanArt?.replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '') ?? '';
      newVideos.poster = resp.poster?.replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '') ?? '';
      newVideos.trailer = resp.trailer;
      newVideos.site = 'R18';

      if (videos.actress != null) {
        for (var i = 0; i < videos.actress!.length; i++) {
          if (videos.actress![i].imageUrl == '') {
            HelperToast.warn('konstol');
          }
        }
      }

      // newVideos.actress = <VideoActress>[];
      // for (var i = 0; i < resp['actors'].length; i++) {
      //   newVideos.actress?.add(VideoActress(
      //     id: resp['actors'][i]['cast_id'],
      //     nameRomaji: resp['actors'][i]['cast_names'],
      //     imageUrl: resp['actors'][i]['cast_image'],
      //   ));
      // }

      newVideos.category = <VideoCategory>[];
      if (resp.genre != null) {
        for (var i = 0; i < resp.genre!.length; i++) {
          newVideos.category?.add(VideoCategory(id: i, category: resp.genre![i]));
        }
      }

      newVideos.releaseDate = resp.releaseDate;
      newVideos.releaseDateFormated = resp.releaseDateFormated;
      newVideos.duration = resp.duration;
      newVideos.durationFormated = resp.durationFormated;

      newVideos.studio = resp.studio;
      newVideos.label = resp.label;
      newVideos.director = resp.director;
      newVideos.series = resp.series;

      newVideos.screenshot = <String>[];
      if (resp.screenshot != null) {
        for (var i = 0; i < resp.screenshot!.length; i++) {
          if (resp.screenshot![i].toString().contains('jp-')) {
            newVideos.screenshot?.add(resp.screenshot![i].replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', ''));
          } else {
            newVideos.screenshot?.add(resp.screenshot![i].replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '').replaceAll('-', 'jp-'));
          }
        }
      }

      DBVideos.update(newVideos);
      HelperToast.success('${newVideos.videoCode} metadata updated');
    }).catchError((e) {
      HelperLoading.dismiss();
      HelperToast.error(e.toString());
    });
  }

  Future<void> onSearch() async {
    if (viewModeSelected.value == kGrid) {
      if (scrollGridController.hasClients) scrollGridController.animToTop();
    } else {
      if (scrollListController.hasClients) scrollListController.animToTop();
    }

    if (tecSearch.text.isEmpty) {
      await onReset();
      return;
    }

    videos.value = await DBVideos.search(tecSearch.text);
    fnSearch.requestFocus();
    isSearchMode.value = true;
  }

  Future<void> onReset() async {
    tecSearch.text = '';
    videos.value = await DBVideos.getAll();
    fnSearch.requestFocus();
    isSearchMode.value = false;
  }
}

// ────────────────────────────────────────────────────────────────
// ────────────────────────────────────────────────────────────────
// # viewMode
const kGrid = 'grid';
const kList = 'list';
