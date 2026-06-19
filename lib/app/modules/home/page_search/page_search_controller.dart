import 'dart:async';

import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';

import '../../../../env.g.dart';
import '../../../core/app_logging.dart';
import '../../../data/api/api_javit.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_loading.dart';
import '../../../utils/helper_opener.dart';
import '../../../utils/helper_toast.dart';
import '../../../utils/semantic_search_service.dart';

class PageSearchController extends GetxController {
  final tecSearch = TextEditingController();
  final isSearchMode = false.obs;
  final isSemanticMode = false.obs;
  final isSemanticBusy = false.obs;
  final fnSearch = FocusNode();
  final phSearch = ''.obs;
  final semanticResultLabel = ''.obs;
  final semanticScoreByVideoId = <String, double>{}.obs;

  final scrollGridController = ScrollController();

  // sort by
  final sortBy = 'random'.obs; // [random, release_date, view_count, filesize, has sub]
  
  // filter
  final filter = VideoFilterState();
  

  final videos = <Videos>[].obs;
  final allVideos = <Videos>[].obs;
  final isFresh = true.obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    await onRefresh();
  }

  Future<void> onRefresh() async {
    final sw = Stopwatch()..start();

    isFresh.value = await DBVideos.getCount() == 0;
    _updatePlaceholder();
    await onReset();

    AppLog.logI('page search ==> onInit called: ${sw.elapsedMilliseconds} ms');
  }

  @override
  void onClose() {
    tecSearch.dispose();
    fnSearch.dispose();
    scrollGridController.dispose();
    super.onClose();
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

      // fix fantart
      newVideos.fanArt = '${Env.apiUrl}/api?image=https://img3.javmost.com/images/480/${videos.videoCode}.webp';

      // ** only apply if actress is null
      if (videos.actress.isEmptyOrNull) {
        if (!resp.actress.isEmptyOrNull) {
          newVideos.actress = <VideoActress>[];
          for (var i = 0; i < resp.actress!.length; i++) {
            newVideos.actress?.add(VideoActress(
              id: resp.actress![i].castId,
              nameRomaji: resp.actress![i].castNames,
              imageUrl: resp.actress![i].castImage,
            ));
          }
        }
      }

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
    if (tecSearch.text.isEmpty) {
      await onReset();
      return;
    }

    if (isSemanticMode.isTrue) {
      await onSemanticSearch();
      return;
    }

    semanticResultLabel.value = '';
    semanticScoreByVideoId.clear();
    videos.value = await DBVideos.search(tecSearch.text);
    fnSearch.requestFocus();
    isSearchMode.value = true;
  }

  Future<void> onSemanticSearch() async {
    isSemanticBusy.value = true;
    try {
      final hits = await SemanticSearchService.search(tecSearch.text);
      semanticScoreByVideoId.clear();
      for (final hit in hits) {
        final videoId = (hit.video.id ?? '').trim();
        if (videoId.isNotEmpty) {
          semanticScoreByVideoId[videoId] = hit.score;
        }
      }

      videos.value = hits.map((item) => item.video).toList();
      semanticResultLabel.value = 'AI Search';
      fnSearch.requestFocus();
      isSearchMode.value = true;
    } catch (e) {
      await HelperToast.error(e.toString());
    } finally {
      isSemanticBusy.value = false;
    }
  }

  Future<void> onReset() async {
    tecSearch.text = '';
    sortBy.value = 'Random';
    semanticResultLabel.value = '';
    semanticScoreByVideoId.clear();
    videos.value = await DBVideos.getAll();
    allVideos.value = videos.value;
    videos.shuffle();
    fnSearch.requestFocus();
    isSearchMode.value = false;
  }

  Future<void> toggleSemanticMode() async {
    isSemanticMode.toggle();
    _updatePlaceholder();
    if (tecSearch.text.trim().isNotEmpty) {
      await onSearch();
    } else {
      await onReset();
    }
  }


  Future<void> onSortByChange(String s) async {
    sortBy.value = s;
    final current = videos.toList();
    List<Videos> next = current;

    switch (s.toLowerCase()) {
      case 'random':
        current.shuffle();
        next = current;
        break;
      case 'release date':
        current.sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
        next = current.where((v) => (v.videoCode ?? '').isNotEmpty).toList();
        break;
      case 'view count':
        current.sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
        next = current;
        break;
      case 'file size':
        current.sort((a, b) => (b.filesize ?? 0).compareTo(a.filesize ?? 0));
        next = current;
        break;
      default:
    }

    videos.value = next;
    
    fnSearch.requestFocus();
  }


  // filter
  final _filterAdapter = VideoFilterAdapter<Videos>(
    videoCode: (video) => video.videoCode ?? '',
    actresses: (video) => (video.actress ?? []).map((actress) => actress.nameRomaji ?? ''),
    categories: (video) => (video.category ?? []).map((category) => category.category ?? ''),
    releaseDate: (video) => video.releaseDate,
  );

  Future<void> openDialogFilter() async {
    await HelperOpener.openFilterDialog<Videos>(
      state: filter,
      allVideos: allVideos.toList(),
      videos: videos,
      adapter: _filterAdapter,
    );
  }

  void _updatePlaceholder() {
    phSearch.value = isSemanticMode.isTrue
        ? 'Local AI Search... ex: subtitle indo outdoor'
        : 'Video Code or Title or Path...';
  }

}
