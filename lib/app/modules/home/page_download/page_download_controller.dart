import 'package:ex_kit/ex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/api/api_javit.dart';
import '../../../data/database/db_videos.dart';
import '../../../data/models/__javit_search_entity.dart';

class PageDownloadController extends GetxController {
  final tecSearch = TextEditingController();
  final fnSearch = FocusNode();
  final phSearch = ''.obs;
  final currentLang = 'en'.obs;

  final api = Get.find<ApiJavit>();
  final response = JavitSearch().obs;
  final hasNextPage = false.obs;
  final currentPage = 0.obs;
  final videos = <JavitSearchResult>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    logS('page download ==> onInit called');
    phSearch.value = await DBVideos.getRandomVideoCode();
    await onReset();
  }

  Future<void> onSearch(String s) async {
    if (s.isEmpty) { await onReset(); return; }

    ExLoading.show(paddingSymmetric: 230);
    response.value = await api.search(s: s, lang: currentLang.value, page: currentPage.value);
    hasNextPage.value = response.value.hasNextPage ?? false;
    currentPage.value = response.value.page ?? 1;
    videos.value = response.value.result ?? [];
    fnSearch.requestFocus();
    ExLoading.dismiss();
  }

  Future<void> onNextPage() async {
    currentPage.value++;
    await onSearch(tecSearch.text);
  }

  Future<void> onPreviousPage() async {
    if (currentPage.value > 1) {
      currentPage.value--;
      await onSearch(tecSearch.text);
    }
  }

  Future<void> onReset() async {
    response.value = JavitSearch();
    currentPage.value = 0;
    hasNextPage.value = false;
    videos.value = [];
    fnSearch.requestFocus();
    
  }
}
