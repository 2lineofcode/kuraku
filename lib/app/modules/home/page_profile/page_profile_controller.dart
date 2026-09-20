import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/app_logging.dart';
import '../../../data/database/db_activity.dart';
import '../../../data/database/db_profile.dart';
import '../../../data/models/profile_entity.dart';
import '../home_controller.dart';

class PageProfileController extends GetxController {
  HomeController get home => Get.find<HomeController>();
  final tecName = TextEditingController();
  final isLoading = false.obs;
  final isSaving = false.obs;
  final isEditing = false.obs;
  final error = ''.obs;
  final nameError = ''.obs;
  final notice = ''.obs;
  final totalRelapse = 0.obs;

  Future<void> onRefresh() async {
    if (isLoading.value || isSaving.value) return;
    isLoading.value = true;
    error.value = '';
    try {
      await home.refreshProfile();
      final count = await DBActivity.countRelapse();
      if (!isClosed) totalRelapse.value = count;
    } catch (e) {
      AppLog.logW('Loading profile failed: $e');
      if (!isClosed) error.value = 'Could not load profile. Please try again.';
    } finally {
      if (!isClosed) isLoading.value = false;
    }
  }

  void editName() {
    tecName.text = home.profile.value.name ?? '';
    nameError.value = '';
    notice.value = '';
    isEditing.value = true;
  }

  void cancelEdit() {
    if (isSaving.value) return;
    tecName.text = home.profile.value.name ?? '';
    nameError.value = '';
    isEditing.value = false;
  }

  Future<void> saveName() async {
    if (isSaving.value) return;
    final name = tecName.text.trim();
    if (name.isEmpty) {
      nameError.value = 'Please enter your name.';
      return;
    }
    isSaving.value = true;
    nameError.value = '';
    try {
      await DBProfile.updateName(name);
      home.profile.value = Profile.fromJson(home.profile.value.toJson()..['name'] = name);
      if (!isClosed) {
        isEditing.value = false;
        notice.value = 'Profile saved';
      }
    } catch (e) {
      AppLog.logW('Saving profile failed: $e');
      if (!isClosed) nameError.value = 'Could not save your name. Please try again.';
    } finally {
      if (!isClosed) isSaving.value = false;
    }
  }

  @override
  void onClose() {
    tecName.dispose();
    super.onClose();
  }
}
