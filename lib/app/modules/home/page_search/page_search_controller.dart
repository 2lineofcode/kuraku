import 'dart:async';
import 'dart:typed_data';

import 'package:ex_kit/ex.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:overlayment/overlayment.dart';
import 'package:video_compress/video_compress.dart';

import '../../../data/api/api_javit.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/videos_entity.dart';
import '../../../utils/helper_misc.dart';
import '../../../utils/helper_toast.dart';
import '../home_controller.dart';

class PageSearchController extends GetxController {
  final tecSearch = TextEditingController();
  final fnSearch = FocusNode();
  final viewModeSelected = ''.obs; // grid | list

  final videos = <Videos>[].obs;
  final Map<String, Uint8List> _thumbnailCache = {};

  final api = Get.find<ApiJavit>();
  @override
  Future<void> onInit() async {
    super.onInit();
    viewModeSelected.value = 'grid';
    videos.value = await DBVideos.getAll();
  }

  void renewMetadata(Videos videos) async {
    await Overlayment.dismissLast();
    ExLoading.show(paddingSymmetric: 240);
    await api.getByCode(code: videos.videoCode ?? '').then((resp) {
      ExLoading.dismiss();
      final newVideos = videos;
      newVideos.title = resp['title'];
      newVideos.titleJa = resp['title_ja'];

      newVideos.description = resp['description'];
      newVideos.fanArt = resp['fan_art'].replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '') ?? '';
      newVideos.poster = resp['poster'].replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '') ?? '';
      newVideos.trailer = resp['trailer'];
      newVideos.site = 'FANZA';

      newVideos.actress = <VideoActress>[];
      for (var i = 0; i < resp['actors'].length; i++) {
        newVideos.actress?.add(VideoActress(
          id: resp['actors'][i]['cast_id'],
          nameRomaji: resp['actors'][i]['cast_names'],
          imageUrl: resp['actors'][i]['cast_image'],
        ));
      }

      newVideos.category = <VideoCategory>[];
      for (var i = 0; i < resp['genre'].length; i++) {
        newVideos.category?.add(VideoCategory(id: i, category: resp['genre'][i]));
      }

      newVideos.releaseDate = resp['release_date'];
      newVideos.releaseDateFormated = resp['release_date_formated'];
      newVideos.duration = resp['duration'];
      newVideos.durationFormated = resp['duration_formated'];

      newVideos.studio = resp['studio'];
      newVideos.label = resp['studio'];
      newVideos.director = resp['studio'];
      newVideos.series = resp['series'] ?? '';

      newVideos.screenshot = <String>[];
      for (var i = 0; i < resp['screenshot'].length; i++) {
        if (resp['screenshot'][i].toString().contains('jp-')) {
          newVideos.screenshot?.add(resp['screenshot'][i].replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '') ?? '');
        } else {
          newVideos.screenshot?.add(resp['screenshot'][i].replaceAll('https://pics.dmm.co.jp/', '').replaceAll('.jpg', '').replaceAll('-', 'jp-') ?? '');
        }
      }
      DBVideos.update(newVideos);
      HelperToast.success('${newVideos.videoCode} metadata updated');
      Get.find<HomeController>().onRefreshAllContent();
    
    }).catchError((e) {
      ExLoading.dismiss();
      HelperToast.error(e.toString());
    });
  }

  Future<List<String>> getMediaInfo(String path) async {
    final output = <String>[];
    ExLoading.show(paddingSymmetric: 240);
    await FFprobeKit.getMediaInformation(path).then((value) async {
      ExLoading.dismiss();
      final medinfo = value.getMediaInformation();
      final stream = value.getMediaInformation()?.getStreams().first;
      output.add('${stream?.getWidth()}x${stream?.getHeight()}'); // -- [0] width x height
      output.add('${stream?.getHeight()}p'); // -- [1] resolution
      output.add('${int.parse(medinfo!.getSize()!).toFileSize()}'); // -- [2] file size
      output.add('${HelperMisc.durationFormat2(num.parse(medinfo.getFormatProperties()!['duration'].toString()))}'); // -- [3] duration
    }).catchError((e) {
      ExLoading.dismiss();
      HelperToast.error(e.toString());
    });

    return output;
  }

  Future<void> onSearch() async {
    if (tecSearch.text.isEmpty) {
      await onReset();
      return;
    }

    videos.value = await DBVideos.search(tecSearch.text);
    fnSearch.requestFocus();
  }

  Future<void> onReset() async {
    tecSearch.text = '';
    videos.value = await DBVideos.getAll();
    fnSearch.requestFocus();
  }

  Future<Uint8List?> getThumbnail(String videopath) async {
    if (_thumbnailCache.containsKey(videopath)) {
      return _thumbnailCache[videopath];
    }

    try {
      final uint8list = await VideoCompress.getByteThumbnail(videopath, quality: 10, position: 10);

      if (uint8list != null) {
        _thumbnailCache[videopath] = uint8list;
      }
      return uint8list;
    } catch (e) {
      print('Error fetching thumbnail for path $videopath: $e');
      return null;
    }
  }
}
