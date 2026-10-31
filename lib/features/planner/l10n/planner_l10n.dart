import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:streak/l10n/app_localizations.dart';
import 'package:streak/features/planner/data/planner_models.dart';

/// Planner labels use the same ARB delegate as the existing Streak screens.
extension PlannerLocalization on BuildContext {
  String plannerText(String key, [Map<String, String> args = const {}]) {
    return _plannerText(AppLocalizations.of(this), key, args);
  }
}

String plannerTextForLocale(
  String locale,
  String key, [
  Map<String, String> args = const {},
]) => _plannerText(
  lookupAppLocalizations(
    Locale(locale.split(RegExp('[_-]')).first == 'ar' ? 'ar' : 'en'),
  ),
  key,
  args,
);

String _plannerText(AppLocalizations l, String key, Map<String, String> args) {
  return switch (key) {
    'cloudExportDraft' => l.planner_cloudExportDraft,
    'cloudPasswordRule' => l.planner_cloudPasswordRule,
    'cloudQueueFull' => l.planner_cloudQueueFull,
    'cloudAccount' => l.planner_cloudAccount,
    'cloudSignIn' => l.planner_cloudSignIn,
    'cloudRegister' => l.planner_cloudRegister,
    'cloudEmail' => l.planner_cloudEmail,
    'cloudPassword' => l.planner_cloudPassword,
    'cloudConfirmPassword' => l.planner_cloudConfirmPassword,
    'cloudShowPassword' => l.planner_cloudShowPassword,
    'cloudHidePassword' => l.planner_cloudHidePassword,
    'cloudPasswordsDoNotMatch' => l.planner_cloudPasswordsDoNotMatch,
    'cloudForgotPassword' => l.planner_cloudForgotPassword,
    'cloudResetPassword' => l.planner_cloudResetPassword,
    'cloudResetCode' => l.planner_cloudResetCode,
    'cloudResetRequestInfo' => l.planner_cloudResetRequestInfo,
    'cloudResetCodeInfo' => l.planner_cloudResetCodeInfo,
    'cloudResetLinkInfo' => l.planner_cloudResetLinkInfo,
    'cloudResetLinkRequestInfo' => l.planner_cloudResetLinkRequestInfo,
    'cloudResendLink' => l.planner_cloudResendLink,
    'cloudContinueWithoutAccount' => l.planner_cloudContinueWithoutAccount,
    'cloudGuest' => l.planner_cloudGuest,
    'cloudResetLinkSent' => l.planner_cloudResetLinkSent,
    'cloudReturnToSignIn' => l.planner_cloudReturnToSignIn,
    'cloudResetSent' => l.planner_cloudResetSent,
    'cloudResetComplete' => l.planner_cloudResetComplete,
    'cloudResetUnavailable' => l.planner_cloudResetUnavailable,
    'cloudResetInvalid' => l.planner_cloudResetInvalid,
    'cloudGoogleSignIn' => l.planner_cloudGoogleSignIn,
    'cloudGoogleLink' => l.planner_cloudGoogleLink,
    'cloudGoogleCanceled' => l.planner_cloudGoogleCanceled,
    'cloudGoogleUnavailable' => l.planner_cloudGoogleUnavailable,
    'cloudGoogleConfiguration' => l.planner_cloudGoogleConfiguration,
    'cloudGoogleCredentialRejected' => l.planner_cloudGoogleCredentialRejected,
    'cloudGoogleProviderDisabled' => l.planner_cloudGoogleProviderDisabled,
    'cloudGoogleLinkRequired' => l.planner_cloudGoogleLinkRequired,
    'cloudGoogleEmailMismatch' => l.planner_cloudGoogleEmailMismatch,
    'cloudGoogleAlreadyLinked' => l.planner_cloudGoogleAlreadyLinked,
    'cloudPrivacy' => l.planner_cloudPrivacy,
    'cloudSignInHint' => l.planner_cloudSignInHint,
    'cloudSyncNow' => l.planner_cloudSyncNow,
    'cloudSignOut' => l.planner_cloudSignOut,
    'cloudUnconfigured' => l.planner_cloudUnconfigured,
    'cloudOffline' => l.planner_cloudOffline,
    'cloudSynced' => l.planner_cloudSynced,
    'cloudSyncing' => l.planner_cloudSyncing,
    'cloudPending' => l.planner_cloudPending(args['count'] ?? ''),
    'cloudConflict' => l.planner_cloudConflict,
    'cloudRejected' => l.planner_cloudRejected,
    'cloudRestoreCloud' => l.planner_cloudRestoreCloud,
    'cloudRestoreInfo' => l.planner_cloudRestoreInfo,
    'cloudSessionExpired' => l.planner_cloudSessionExpired,
    'cloudFirestorePermissionDenied' =>
      l.planner_cloudFirestorePermissionDenied,
    'cloudFirestoreUnauthenticated' => l.planner_cloudFirestoreUnauthenticated,
    'cloudFirestorePrecondition' => l.planner_cloudFirestorePrecondition,
    'cloudNetworkError' => l.planner_cloudNetworkError,
    'cloudInvalidCredentials' => l.planner_cloudInvalidCredentials,
    'cloudEmailExists' => l.planner_cloudEmailExists,
    'cloudEmailProviderDisabled' => l.planner_cloudEmailProviderDisabled,
    'cloudAccountDisabled' => l.planner_cloudAccountDisabled,
    'cloudFirebaseConfiguration' => l.planner_cloudFirebaseConfiguration,
    'cloudInvalidEmail' => l.planner_cloudInvalidEmail,
    'cloudInvalidPassword' => l.planner_cloudInvalidPassword,
    'cloudAuthFailed' => l.planner_cloudAuthFailed,
    'cloudRateLimited' => l.planner_cloudRateLimited,
    'cloudServerUnavailable' => l.planner_cloudServerUnavailable,
    'cloudRestoring' => l.planner_cloudRestoring,
    'cloudSignOutInfo' => l.planner_cloudSignOutInfo,
    'cloudKeepOffline' => l.planner_cloudKeepOffline,
    'cloudDraftArchived' => l.planner_cloudDraftArchived,
    'cloudLocalOnly' => l.planner_cloudLocalOnly,
    'completionShort' => l.planner_completionShort,
    'failureShort' => l.planner_failureShort,
    'taskSkipShort' => l.planner_taskSkipShort,
    'skipDeduction' => l.planner_skipDeduction(args['xp'] ?? ''),
    'builderIdentity' => l.planner_builderIdentity,
    'builderTasks' => l.planner_builderTasks,
    'builderRewards' => l.planner_builderRewards,
    'builderStep' => l.planner_builderStep(
      args['current'] ?? '',
      args['total'] ?? '',
    ),
    'builderNext' => l.planner_builderNext,
    'builderPrevious' => l.planner_builderPrevious,
    'builderIdentityHint' => l.planner_builderIdentityHint,
    'builderTasksHint' => l.planner_builderTasksHint,
    'builderRewardsHint' => l.planner_builderRewardsHint,
    'categoryName' => l.planner_categoryName,
    'newCategory' => l.planner_newCategory,
    'manageCategories' => l.planner_manageCategories,
    'renameCategory' => l.planner_renameCategory,
    'deleteCategory' => l.planner_deleteCategory,
    'noCategory' => l.planner_noCategory,
    'categoryDeleteInfo' => l.planner_categoryDeleteInfo,
    'noCategories' => l.planner_noCategories,
    'addTaskGroup' => l.planner_addTaskGroup,
    'taskGroup' => l.planner_taskGroup,
    'groupName' => l.planner_groupName,
    'editGroup' => l.planner_editGroup,
    'groupChildren' => _plannerPluralDigits(
      l,
      l.planner_groupChildren(_plannerCount(args)),
    ),
    'emptyGroup' => l.planner_emptyGroup,
    'parentPackage' => l.planner_parentPackage,
    'returnToParent' => l.planner_returnToParent,
    'flexibleTask' => l.planner_flexibleTask,
    'flexibleTaskHint' => l.planner_flexibleTaskHint,
    'scheduledTask' => l.planner_scheduledTask,
    'scheduledTaskHint' => l.planner_scheduledTaskHint,
    'taskType' => l.planner_taskType,
    'chooseStartTime' => l.planner_chooseStartTime,
    'chooseEndTime' => l.planner_chooseEndTime,
    'invalidTaskInterval' => l.planner_invalidTaskInterval,
    'taskTimeConflict' => l.planner_taskTimeConflict,
    'optionalReminder' => l.planner_optionalReminder,
    'packageRewardLabel' => l.planner_packageRewardLabel,
    'packagePenalty' => l.planner_packagePenalty,
    'savePackage' => l.planner_savePackage,
    'packagePreview' => l.planner_packagePreview,
    'packageTaskCount' => _plannerPluralDigits(
      l,
      l.planner_packageTaskCount(_plannerCount(args)),
    ),
    'preservedConditions' => l.planner_preservedConditions,
    'preservedConditionsInfo' => l.planner_preservedConditionsInfo,
    'noTasksYet' => l.planner_noTasksYet,
    'groupDeleteInfo' => l.planner_groupDeleteInfo,
    'deleteTaskInfo' => l.planner_deleteTaskInfo,
    'packageSummaryShort' => _plannerPluralDigits(
      l,
      l.planner_packageSummaryShort(_plannerCount(args), args['xp'] ?? ''),
    ),
    'groupProgress' => l.planner_groupProgress(
      args['done'] ?? '',
      args['total'] ?? '',
    ),
    'groupCompletionRule' => l.planner_groupCompletionRule,
    'skipPackageTaskInfo' => l.planner_skipPackageTaskInfo,
    'legacyRewardRules' => l.planner_legacyRewardRules,
    'invalidCategoryName' => l.planner_invalidCategoryName,
    'categoryNameExists' => l.planner_categoryNameExists,
    'categoryMissing' => l.planner_categoryMissing,
    'invalidTaskTree' => l.planner_invalidTaskTree,
    'groupChildrenFirst' => l.planner_groupChildrenFirst,
    'skipOptionalPackageTaskInfo' => l.planner_skipOptionalPackageTaskInfo,
    'timeline' => l.planner_timeline,
    'returnToday' => l.planner_returnToday,
    'now' => l.planner_now,
    'freeTime' => l.planner_freeTime,
    'allDay' => l.planner_allDay,
    'emptyTimeline' => l.planner_emptyTimeline,
    'continuesPreviousDay' => l.planner_continuesPreviousDay,
    'continuesNextDay' => l.planner_continuesNextDay,
    'overlaps' => l.planner_overlaps,
    'earlierDays' => l.planner_earlierDays,
    'timelineEvent' => l.planner_timelineEvent(
      args['title'] ?? '',
      args['start'] ?? '',
      args['end'] ?? '',
      args['status'] ?? '',
      args['type'] ?? '',
    ),
    'today' => l.planner_today,
    'schedule' => l.planner_schedule,
    'challenges' => l.planner_challenges,
    'profile' => l.planner_profile,
    'addRoutine' => l.planner_addRoutine,
    'routine' => l.planner_routine,
    'todaysChallenge' => l.planner_todaysChallenge,
    'noRoutine' => l.planner_noRoutine,
    'noChallenge' => l.planner_noChallenge,
    'tomorrow' => l.planner_tomorrow,
    'chooseTomorrow' => l.planner_chooseTomorrow,
    'choosePackage' => l.planner_choosePackage,
    'templates' => l.planner_templates,
    'history' => l.planner_history,
    'createPackage' => l.planner_createPackage,
    'editPackage' => l.planner_editPackage,
    'duplicate' => l.planner_duplicate,
    'edit' => l.planner_edit,
    'delete' => l.planner_delete,
    'confirmDelete' => l.planner_confirmDelete,
    'deleteTemplateInfo' => l.planner_deleteTemplateInfo,
    'packageName' => l.planner_packageName,
    'description' => l.planner_description,
    'difficulty' => l.planner_difficulty,
    'easy' => l.planner_easy,
    'medium' => l.planner_medium,
    'hard' => l.planner_hard,
    'tasks' => l.planner_tasks,
    'addTask' => l.planner_addTask,
    'editTask' => l.planner_editTask,
    'taskTitle' => l.planner_taskTitle,
    'save' => l.planner_save,
    'cancel' => l.planner_cancel,
    'advanced' => l.planner_advanced,
    'durationDays' => l.planner_durationDays,
    'completionReward' => l.planner_completionReward,
    'failurePenalty' => l.planner_failurePenalty,
    'taskReward' => l.planner_taskReward,
    'skipPenalty' => l.planner_skipPenalty,
    'durationMinutes' => l.planner_durationMinutes,
    'taskDays' => l.planner_taskDays,
    'sequentialSteps' => l.planner_sequentialSteps,
    'target' => l.planner_target,
    'unit' => l.planner_unit,
    'mandatory' => l.planner_mandatory,
    'taskTime' => l.planner_taskTime,
    'clearTime' => l.planner_clearTime,
    'moveUp' => l.planner_moveUp,
    'moveDown' => l.planner_moveDown,
    'emptyTemplates' => l.planner_emptyTemplates,
    'noHistory' => l.planner_noHistory,
    'commitment' => l.planner_commitment,
    'previewPackage' => l.planner_previewPackage,
    'selectForDate' => l.planner_selectForDate(args['date'] ?? ''),
    'confirmAssignment' => l.planner_confirmAssignment,
    'assignmentLocked' => l.planner_assignmentLocked,
    'packageReward' => l.planner_packageReward(args['xp'] ?? ''),
    'taskRewardSummary' => l.planner_taskRewardSummary(args['xp'] ?? ''),
    'skipPenaltySummary' => l.planner_skipPenaltySummary(args['xp'] ?? ''),
    'failurePenaltySummary' => l.planner_failurePenaltySummary(
      args['xp'] ?? '',
    ),
    'commitmentSummary' => l.planner_commitmentSummary(
      args['days'] ?? '',
      args['minutes'] ?? '',
      args['xp'] ?? '',
    ),
    'active' => l.planner_active,
    'completed' => l.planner_completed,
    'failed' => l.planner_failed,
    'pending' => l.planner_pending,
    'skipped' => l.planner_skipped,
    'remainingTasks' => l.planner_remainingTasks,
    'deadline' => l.planner_deadline,
    'selectedForTomorrow' => l.planner_selectedForTomorrow,
    'selectionMissed' => l.planner_selectionMissed,
    'selectionPenaltyApplied' => l.planner_selectionPenaltyApplied(
      args['xp'] ?? '',
    ),
    'selectionDeadline' => l.planner_selectionDeadline,
    'missedSelectionPenalty' => l.planner_missedSelectionPenalty,
    'dailySelection' => l.planner_dailySelection,
    'settings' => l.planner_settings,
    'xpHistory' => l.planner_xpHistory,
    'achievements' => l.planner_achievements,
    'noXpHistory' => l.planner_noXpHistory,
    'nextLevelXp' => l.planner_nextLevelXp(args['xp'] ?? ''),
    'levelXp' => l.planner_levelXp(args['level'] ?? '', args['xp'] ?? ''),
    'levelShort' => l.planner_levelShort(args['level'] ?? ''),
    'authOr' => l.planner_authOr,
    'habitFocusTools' => l.planner_habitFocusTools,
    'reminderAccess' => l.planner_reminderAccess,
    'notificationAccess' => l.planner_notificationAccess,
    'preciseReminders' => l.planner_preciseReminders,
    'about' => l.planner_about,
    'noAchievements' => l.planner_noAchievements,
    'allTasksComplete' => l.planner_allTasksComplete,
    'previousWeek' => l.planner_previousWeek,
    'nextWeek' => l.planner_nextWeek,
    'completedTasks' => l.planner_completedTasks(
      args['done'] ?? '',
      args['total'] ?? '',
    ),
    'selectionRulesInfo' => l.planner_selectionRulesInfo(
      args['time'] ?? '',
      args['xp'] ?? '',
    ),
    'acknowledged' => l.planner_acknowledged,
    'invalidPackageName' => l.planner_invalidPackageName,
    'packageNeedsTask' => l.planner_packageNeedsTask,
    'invalidTaskTitle' => l.planner_invalidTaskTitle,
    'requiredValue' => l.planner_requiredValue,
    'packageTasksPackage' => l.planner_packageTasksPackage,
    'packageDays' => l.planner_packageDays,
    'recordedXp' => l.planner_recordedXp,
    'language' => l.planner_language,
    'moreSettings' => l.planner_moreSettings,
    'chooseTime' => l.planner_chooseTime,
    'xp' => l.planner_xp,
    'noTasks' => l.planner_noTasks,
    'selected' => l.planner_selected,
    'missed' => l.planner_missed,
    'penaltyRecorded' => l.planner_penaltyRecorded,
    'perTask' => l.planner_perTask,
    'packageDuration' => l.planner_packageDuration,
    'requiredTasksRule' => l.planner_requiredTasksRule,
    'taskOrder' => l.planner_taskOrder,
    'dueDay' => l.planner_dueDay,
    'remind' => l.planner_remind,
    'replaceDatesInfo' => l.planner_replaceDatesInfo,
    'tomorrowPrompt' => l.planner_tomorrowPrompt(args['date'] ?? ''),
    'selectionMissedNotice' => l.planner_selectionMissedNotice,
    'noCancel' => l.planner_noCancel,
    'amountProgress' => l.planner_amountProgress(
      args['amount'] ?? '',
      args['target'] ?? '',
      args['unit'] ?? '',
    ),
    'createActivity' => l.planner_createActivity,
    'createRoutine' => l.planner_createRoutine,
    'createTask' => l.planner_createTask,
    'editActivity' => l.planner_editActivity,
    'deleteActivity' => l.planner_deleteActivity,
    'title' => l.planner_title,
    'titleHint' => l.planner_titleHint,
    'invalidActivityTitle' => l.planner_invalidActivityTitle,
    'descriptionOptional' => l.planner_descriptionOptional,
    'category' => l.planner_category,
    'categoryPersonal' => l.planner_categoryPersonal,
    'categoryStudy' => l.planner_categoryStudy,
    'categoryWork' => l.planner_categoryWork,
    'categoryFitness' => l.planner_categoryFitness,
    'categoryRest' => l.planner_categoryRest,
    'when' => l.planner_when,
    'firstDate' => l.planner_firstDate,
    'scheduledBlock' => l.planner_scheduledBlock,
    'withoutFixedTime' => l.planner_withoutFixedTime,
    'startTime' => l.planner_startTime(args['time'] ?? ''),
    'endTime' => l.planner_endTime(args['time'] ?? ''),
    'endsNextDay' => l.planner_endsNextDay,
    'crossesMidnight' => l.planner_crossesMidnight,
    'applyChangesTo' => l.planner_applyChangesTo,
    'entireSeries' => l.planner_entireSeries,
    'onlyOccurrence' => l.planner_onlyOccurrence,
    'repeat' => l.planner_repeat,
    'onceOnly' => l.planner_onceOnly,
    'everyDay' => l.planner_everyDay,
    'selectedWeekdays' => l.planner_selectedWeekdays,
    'everyNWeeks' => l.planner_everyNWeeks,
    'repeatWeeks' => l.planner_repeatWeeks,
    'invalidWeeks' => l.planner_invalidWeeks,
    'remindMe' => l.planner_remindMe,
    'repeatsScheduled' => l.planner_repeatsScheduled,
    'reminderTimeAt' => l.planner_reminderTimeAt(args['time'] ?? ''),
    'reminderSound' => l.planner_reminderSound,
    'defaultSoundPreview' => l.planner_defaultSoundPreview,
    'selectedSystemTone' => l.planner_selectedSystemTone,
    'vibrate' => l.planner_vibrate,
    'androidReminderInfo' => l.planner_androidReminderInfo,
    'stepsGoals' => l.planner_stepsGoals,
    'orderedSteps' => l.planner_orderedSteps,
    'oneStepPerLine' => l.planner_oneStepPerLine,
    'allStepsInOrder' => l.planner_allStepsInOrder,
    'optionalTarget' => l.planner_optionalTarget,
    'targetExample' => l.planner_targetExample,
    'positiveTarget' => l.planner_positiveTarget,
    'unitHint' => l.planner_unitHint,
    'addUnit' => l.planner_addUnit,
    'prerequisitesOptional' => l.planner_prerequisitesOptional,
    'prerequisiteInfo' => l.planner_prerequisiteInfo,
    'saving' => l.planner_saving,
    'saveActivity' => l.planner_saveActivity,
    'saveTask' => l.planner_saveTask,
    'invalidOvernight' => l.planner_invalidOvernight,
    'invalidEndTime' => l.planner_invalidEndTime,
    'selectRepeatDay' => l.planner_selectRepeatDay,
    'activitiesOverlap' => l.planner_activitiesOverlap,
    'overlapSaveInfo' => l.planner_overlapSaveInfo(args['names'] ?? ''),
    'saveBoth' => l.planner_saveBoth,
    'addedPlanner' => l.planner_addedPlanner,
    'activityUpdated' => l.planner_activityUpdated,
    'deleteActivityQuestion' => l.planner_deleteActivityQuestion,
    'deleteOccurrenceInfo' => l.planner_deleteOccurrenceInfo,
    'deleteSeriesInfo' => l.planner_deleteSeriesInfo,
    'taskDetails' => l.planner_taskDetails,
    'challengeTask' => l.planner_challengeTask,
    'challenge' => l.planner_challenge,
    'routineTask' => l.planner_routineTask,
    'rewardOnce' => l.planner_rewardOnce(args['xp'] ?? ''),
    'overlapNames' => l.planner_overlapNames(args['names'] ?? ''),
    'prerequisites' => l.planner_prerequisites,
    'prerequisitesInfo' => l.planner_prerequisitesInfo,
    'reminderEnabled' => l.planner_reminderEnabled,
    'noReminder' => l.planner_noReminder,
    'adjustReminder' => l.planner_adjustReminder,
    'chooseReminder' => l.planner_chooseReminder,
    'stepsProgress' => l.planner_stepsProgress(
      args['done'] ?? '',
      args['total'] ?? '',
    ),
    'previousStepFirst' => l.planner_previousStepFirst,
    'measuredProgress' => l.planner_measuredProgress,
    'recordAmount' => l.planner_recordAmount,
    'endedPackageInfo' => l.planner_endedPackageInfo,
    'availableOn' => l.planner_availableOn(args['date'] ?? ''),
    'markComplete' => l.planner_markComplete,
    'skipTaskQuestion' => l.planner_skipTaskQuestion,
    'skipInfo' => l.planner_skipInfo(args['xp'] ?? ''),
    'skipTask' => l.planner_skipTask,
    'skipWithPenalty' => l.planner_skipWithPenalty,
    'recordTotalAmount' => l.planner_recordTotalAmount,
    'totalCompleted' => l.planner_totalCompleted,
    'totalNotAdditional' => l.planner_totalNotAdditional,
    'nonnegativeAmount' => l.planner_nonnegativeAmount,
    'goBack' => l.planner_goBack,
    'saveAmount' => l.planner_saveAmount,
    'notificationsBlocked' => l.planner_notificationsBlocked,
    'taskReminder' => l.planner_taskReminder,
    'enableReminder' => l.planner_enableReminder,
    'reminderTime' => l.planner_reminderTime,
    'sound' => l.planner_sound,
    'choosePreviewSound' => l.planner_choosePreviewSound,
    'applyEveryOccurrence' => l.planner_applyEveryOccurrence,
    'fixedPackageRules' => l.planner_fixedPackageRules,
    'saveReminder' => l.planner_saveReminder,
    'anyTime' => l.planner_anyTime,
    'nextDaySuffix' => l.planner_nextDaySuffix,
    'confirm' => l.planner_confirm,
    'timeConflict' => l.planner_timeConflict,
    'overdueDate' => l.planner_overdueDate(args['date'] ?? ''),
    'stepsShort' => l.planner_stepsShort(
      args['done'] ?? '',
      args['total'] ?? '',
    ),
    'routineNoXp' => l.planner_routineNoXp,
    'transactionTaskReward' => l.planner_transactionTaskReward(
      args['title'] ?? '',
    ),
    'transactionPackageReward' => l.planner_transactionPackageReward(
      args['title'] ?? '',
    ),
    'transactionTaskSkip' => l.planner_transactionTaskSkip(args['title'] ?? ''),
    'transactionPackageFailure' => l.planner_transactionPackageFailure(
      args['title'] ?? '',
    ),
    'transactionMissedSelection' => l.planner_transactionMissedSelection(
      args['date'] ?? '',
    ),
    'achievementFirst' => l.planner_achievementFirst,
    'achievementTen' => l.planner_achievementTen,
    'achievementStreak' => l.planner_achievementStreak,
    'achievementPackage' => l.planner_achievementPackage,
    'achievementLevel' => l.planner_achievementLevel,
    'genericError' => l.planner_genericError,
    'minutes' => l.planner_minutes,
    'optional' => l.planner_optional,
    'notificationReady' => l.planner_notificationReady,
    'notificationSilent' => l.planner_notificationSilent,
    'notificationChannel' => l.planner_notificationChannel,
    'notificationChannelDescription' =>
      l.planner_notificationChannelDescription,
    'notificationComplete' => l.planner_notificationComplete,
    'notificationSnooze' => l.planner_notificationSnooze,
    'taskCompleted' => l.planner_taskCompleted,
    'reminderSnoozed' => l.planner_reminderSnoozed,
    'reminderUnavailable' => l.planner_reminderUnavailable,
    'builtinSteadyName' => l.planner_builtinSteadyName,
    'builtinSteadyDescription' => l.planner_builtinSteadyDescription,
    'builtinStudyName' => l.planner_builtinStudyName,
    'builtinStudyDescription' => l.planner_builtinStudyDescription,
    'builtinFitnessName' => l.planner_builtinFitnessName,
    'builtinFitnessDescription' => l.planner_builtinFitnessDescription,
    'builtinFocus' => l.planner_builtinFocus,
    'builtinStudy' => l.planner_builtinStudy,
    'builtinReview' => l.planner_builtinReview,
    'builtinWorkout' => l.planner_builtinWorkout,
    'builtinRecovery' => l.planner_builtinRecovery,
    'builtinPriority' => l.planner_builtinPriority,
    'builtinFocusMinutes' => l.planner_builtinFocusMinutes,
    'builtinNextAction' => l.planner_builtinNextAction,
    'builtinRecall' => l.planner_builtinRecall,
    'builtinQuestion' => l.planner_builtinQuestion,
    'builtinWarmup' => l.planner_builtinWarmup,
    'builtinPlannedWorkout' => l.planner_builtinPlannedWorkout,
    'builtinCooldown' => l.planner_builtinCooldown,
    'builtinRecordSession' => l.planner_builtinRecordSession,
    'achievementSeven' => l.planner_achievementSeven,
    'achievementHard' => l.planner_achievementHard,
    'achievementFifty' => l.planner_achievementFifty,
    'enabled' => l.planner_enabled,
    'disabled' => l.planner_disabled,
    'templateNotFound' => l.planner_templateNotFound,
    'alreadyAssigned' => l.planner_alreadyAssigned,
    'invalidSelectionRules' => l.planner_invalidSelectionRules,
    'errorChallengeEdit' => l.planner_errorChallengeEdit,
    'errorRoutineMissing' => l.planner_errorRoutineMissing,
    'errorTaskMissing' => l.planner_errorTaskMissing,
    'errorTaskDate' => l.planner_errorTaskDate,
    'errorAvailableDate' => l.planner_errorAvailableDate(args['date'] ?? ''),
    'errorPrerequisiteTitle' => l.planner_errorPrerequisiteTitle(
      args['title'] ?? '',
    ),
    'errorTargetFirst' => l.planner_errorTargetFirst,
    'errorNoTarget' => l.planner_errorNoTarget,
    'errorFutureSkip' => l.planner_errorFutureSkip,
    'errorPastChallenge' => l.planner_errorPastChallenge,
    'errorTimes' => l.planner_errorTimes,
    'errorTimeRange' => l.planner_errorTimeRange,
    'errorReminderTime' => l.planner_errorReminderTime,
    'errorReminderLead' => l.planner_errorReminderLead,
    'errorSelfDependency' => l.planner_errorSelfDependency,
    'errorCycle' => l.planner_errorCycle,
    'errorSameDayPrerequisite' => l.planner_errorSameDayPrerequisite,
    'errorUniqueTaskIds' => l.planner_errorUniqueTaskIds,
    'errorTaskRules' => l.planner_errorTaskRules,
    'softChime' => l.planner_softChime,
    'brightChime' => l.planner_brightChime,
    'errorTargetAmount' => l.planner_errorTargetAmount(
      args['amount'] ?? '',
      args['unit'] ?? '',
    ),
    _ => throw ArgumentError.value(key, 'key', 'Unknown planner translation'),
  };
}

int _plannerCount(Map<String, String> args) =>
    int.tryParse(
      plannerLatinDigits((args['count'] ?? '').replaceAll(',', '')),
    ) ??
    0;

String _plannerPluralDigits(AppLocalizations l, String text) =>
    l.localeName.startsWith('ar')
    ? _plannerArabicDigits(text).replaceAll(',', '٬').replaceAll('.', '٫')
    : text;

String plannerNumber(BuildContext context, num number) {
  final text = NumberFormat.decimalPattern(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(number);
  return Localizations.localeOf(context).languageCode == 'ar'
      ? _plannerArabicDigits(text).replaceAll(',', '٬').replaceAll('.', '٫')
      : text;
}

String _plannerArabicDigits(String text) => text.replaceAllMapped(
  RegExp('[0-9]'),
  (match) => '٠١٢٣٤٥٦٧٨٩'[int.parse(match[0]!)],
);

/// Accept both Western and Arabic keyboard digits without changing stored units.
String plannerLatinDigits(String value) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  return value.split('').map((character) {
    final digit = arabic.indexOf(character);
    final extended = persian.indexOf(character);
    return digit >= 0
        ? '$digit'
        : extended >= 0
        ? '$extended'
        : character == '٫' || character == ','
        ? '.'
        : character == '٬'
        ? ''
        : character;
  }).join();
}

num? plannerParseNumber(String value) =>
    num.tryParse(plannerLatinDigits(value).trim());

String plannerLocalDate(
  BuildContext context,
  DateTime day, {
  bool weekday = false,
  bool compact = false,
}) {
  final text =
      (compact
              ? DateFormat.MMMEd
              : weekday
              ? DateFormat.yMMMMEEEEd
              : DateFormat.yMMMd)(
            Localizations.localeOf(context).toLanguageTag(),
          )
          .format(day);
  return Localizations.localeOf(context).languageCode == 'ar'
      ? _plannerArabicDigits(text)
      : text;
}

String plannerWeekday(BuildContext context, int weekday, {bool short = true}) =>
    (short ? DateFormat.E : DateFormat.EEEE)(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(DateTime(2024, 1, weekday));

String plannerCategory(BuildContext context, String category) =>
    switch (category) {
      'Personal' => context.plannerText('categoryPersonal'),
      'Study' => context.plannerText('categoryStudy'),
      'Work' => context.plannerText('categoryWork'),
      'Fitness' => context.plannerText('categoryFitness'),
      'Rest' => context.plannerText('categoryRest'),
      _ => category,
    };

String plannerSoundName(BuildContext context, String name) => switch (name) {
  'Level Up · Soft chime' => context.plannerText('softChime'),
  'Level Up · Bright chime' => context.plannerText('brightChime'),
  _ => name,
};

// Translate the bundled sample text only. User-entered content remains intact.
String plannerTemplateName(BuildContext context, ChallengeTemplate template) =>
    _builtinTemplateIds.contains(template.id)
    ? _plannerBuiltinText(context, template.name)
    : template.name;
String plannerTemplateDescription(
  BuildContext context,
  ChallengeTemplate template,
) => _builtinTemplateIds.contains(template.id)
    ? _plannerBuiltinText(context, template.description)
    : template.description;
String plannerDefinitionTitle(
  BuildContext context,
  ChallengeTaskDefinition task,
) => _builtinTaskIds.contains(task.id)
    ? _plannerBuiltinText(context, task.title)
    : task.title;
List<String> plannerDefinitionSteps(
  BuildContext context,
  ChallengeTaskDefinition task,
) => task.steps
    .map(
      (step) => _builtinTaskIds.contains(task.id)
          ? _plannerBuiltinText(context, step)
          : step,
    )
    .toList();
String plannerOccurrenceTitle(
  BuildContext context,
  PlannerOccurrence occurrence,
) =>
    occurrence.isChallenge &&
        _builtinTaskIds.contains(occurrence.itemId.split('/').last)
    ? _plannerBuiltinText(context, occurrence.title)
    : occurrence.title;
String plannerOccurrenceStep(
  BuildContext context,
  PlannerOccurrence occurrence,
  int index,
) =>
    occurrence.isChallenge &&
        _builtinTaskIds.contains(occurrence.itemId.split('/').last)
    ? _plannerBuiltinText(context, occurrence.item.steps[index])
    : occurrence.item.steps[index];
const _builtinTemplateIds = {
  'steady-start',
  'study-rhythm',
  'fitness-foundation',
};
const _builtinTaskIds = {'focus', 'study', 'review', 'workout', 'recover'};
String plannerUnit(BuildContext context, String unit) =>
    unit == 'minutes' ? context.plannerText('minutes') : unit;
String _plannerBuiltinText(BuildContext context, String value) {
  final key = switch (value) {
    'Steady start' => 'builtinSteadyName',
    'Study rhythm' => 'builtinStudyName',
    'Fitness foundation' => 'builtinFitnessName',
    'Build a deliberate start to your day with a small, repeatable focus block.' =>
      'builtinSteadyDescription',
    'One week of focused study, followed by a short review. Your existing commitments stay in place.' =>
      'builtinStudyDescription',
    'A demanding week of planned movement and recovery. Choose an appropriate exercise intensity for yourself.' =>
      'builtinFitnessDescription',
    'A focused start' => 'builtinFocus',
    'Deep study' => 'builtinStudy',
    'Recall and review' => 'builtinReview',
    'Workout sequence' => 'builtinWorkout',
    'Recovery and mobility' => 'builtinRecovery',
    'Choose one priority' => 'builtinPriority',
    'Focus for 15 minutes' => 'builtinFocusMinutes',
    'Write the next action' => 'builtinNextAction',
    'Recall the key ideas' => 'builtinRecall',
    'Record a question for tomorrow' => 'builtinQuestion',
    'Warm up' => 'builtinWarmup',
    'Complete your planned workout' => 'builtinPlannedWorkout',
    'Cool down' => 'builtinCooldown',
    'Record the session' => 'builtinRecordSession',
    _ => null,
  };
  return key == null ? value : context.plannerText(key);
}

String plannerTransactionReason(BuildContext context, XpTransaction event) {
  String title = event.reason;
  switch (event.type) {
    case 'task_completion':
    case 'task_complete':
      title = title.replaceFirst(RegExp(r'^Completed '), '');
      return context.plannerText('transactionTaskReward', {
        'title': _plannerBuiltinText(context, title),
      });
    case 'challenge_completion':
    case 'package_completion':
      title = title.replaceFirst(RegExp(r'^Completed (package )?'), '');
      return context.plannerText('transactionPackageReward', {
        'title': _plannerBuiltinText(context, title),
      });
    case 'task_skip':
      title = title
          .replaceFirst(RegExp(r'^Skipped '), '')
          .replaceFirst(RegExp(r' \(configured penalty:.*$'), '');
      return context.plannerText('transactionTaskSkip', {
        'title': _plannerBuiltinText(context, title),
      });
    case 'challenge_failure':
    case 'package_failure':
      title = title
          .replaceFirst(RegExp(r'^(Failed |Package failed: )'), '')
          .replaceFirst(RegExp(r' \(configured penalty:.*$'), '');
      return context.plannerText('transactionPackageFailure', {
        'title': _plannerBuiltinText(context, title),
      });
    case 'missed_selection':
    case 'daily_selection_missed':
      final date = DateTime.tryParse(event.relatedId ?? '');
      return context.plannerText('transactionMissedSelection', {
        'date': date == null
            ? (event.relatedId ?? '')
            : plannerLocalDate(context, date),
      });
    default:
      return event.reason;
  }
}

String plannerAchievementTitle(
  BuildContext context,
  PlannerAchievement achievement,
) {
  final key = switch (achievement.id) {
    'first-task' => 'achievementFirst',
    'ten_tasks' => 'achievementTen',
    'seven-days' => 'achievementSeven',
    'first-package' => 'achievementPackage',
    'first-hard' => 'achievementHard',
    'fifty-tasks' => 'achievementFifty',
    'level_five' => 'achievementLevel',
    _ => null,
  };
  return key == null ? achievement.title : context.plannerText(key);
}

/// Domain values are language independent. Translate validation at the boundary.
String plannerError(BuildContext context, Object error) {
  final message = '$error'
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');
  if (message == 'cloud_queue_full') {
    return context.plannerText('cloudQueueFull');
  }
  if (Localizations.localeOf(context).languageCode != 'ar') return message;
  final available = RegExp(
    r'^This task becomes available on (.+)\.$',
  ).firstMatch(message);
  if (available != null) {
    final date = DateTime.tryParse(available[1]!);
    return context.plannerText('errorAvailableDate', {
      'date': date == null ? available[1]! : plannerLocalDate(context, date),
    });
  }
  final prerequisite = RegExp(
    r'^Complete (?:the required preceding task|the prerequisite task|the prerequisite package) first: (.+)\.$',
  ).firstMatch(message);
  if (prerequisite != null) {
    return context.plannerText('errorPrerequisiteTitle', {
      'title': _plannerBuiltinText(context, prerequisite[1]!),
    });
  }
  if (message.startsWith('Reach the target amount')) {
    return context.plannerText('errorTargetFirst');
  }
  final target = RegExp(
    r'^Record at least (\S+) (.+) first\.$',
  ).firstMatch(message);
  if (target != null) {
    final number = num.tryParse(target[1]!);
    return context.plannerText('errorTargetAmount', {
      'amount': number == null ? target[1]! : plannerNumber(context, number),
      'unit': plannerUnit(context, target[2]!),
    });
  }
  final key = switch (message) {
    'Enter a category name.' => 'invalidCategoryName',
    'A category with this name already exists.' => 'categoryNameExists',
    'Package category not found.' => 'categoryMissing',
    'A parent task group does not exist.' => 'invalidTaskTree',
    'Task groups cannot form a cycle.' => 'invalidTaskTree',
    'A task group needs required children and cannot have task rules.' =>
      'emptyGroup',
    'A package needs required tasks.' => 'packageNeedsTask',
    'Choose a start time for a scheduled task.' => 'chooseStartTime',
    'Choose a reminder time.' => 'reminderTime',
    'Enter a positive target and a unit.' => 'positiveTarget',
    'Enter a finite, non-negative amount.' => 'nonnegativeAmount',
    'Choose a package for tomorrow.' => 'chooseTomorrow',
    'Package template not found.' => 'templateNotFound',
    'A package is already assigned to this date.' => 'alreadyAssigned',
    'Daily selection rules are invalid.' => 'invalidSelectionRules',
    'Complete the prerequisite task first.' => 'prerequisitesInfo',
    'Challenge task definitions cannot be edited.' => 'errorChallengeEdit',
    'The recurring activity no longer exists.' => 'errorRoutineMissing',
    'Task occurrence not found.' => 'errorTaskMissing',
    'This task is no longer available.' => 'errorTaskMissing',
    'Task date is invalid.' => 'errorTaskDate',
    'This task has no amount target.' => 'errorNoTarget',
    'Future tasks cannot be skipped early.' => 'errorFutureSkip',
    'A challenge cannot start in the past.' => 'errorPastChallenge',
    'Set both start and end times.' => 'errorTimes',
    'Times must be within a day.' => 'errorTimeRange',
    'End time must follow start time; enable overnight for a next-day finish.' =>
      'invalidEndTime',
    'Reminder time is invalid.' => 'errorReminderTime',
    'Reminder lead time is invalid.' => 'errorReminderLead',
    'A task cannot depend on itself.' => 'errorSelfDependency',
    'Task prerequisites cannot form a cycle.' => 'errorCycle',
    'Package prerequisites cannot form a cycle.' => 'errorCycle',
    'Package prerequisites must be scheduled on the same day.' =>
      'errorSameDayPrerequisite',
    'Package task identifiers must be unique.' => 'errorUniqueTaskIds',
    'Task rules are invalid.' => 'errorTaskRules',
    'The selection deadline has passed.' => 'selectionMissed',
    'Complete every required step first.' => 'allStepsInOrder',
    'Complete the earlier steps first.' => 'previousStepFirst',
    'An active challenge cannot be cancelled or deleted.' => 'noCancel',
    'This challenge has ended. Its history is read-only.' => 'endedPackageInfo',
    'This challenge has ended.' => 'endedPackageInfo',
    'Select at least one valid weekday.' => 'selectRepeatDay',
    'Weekly interval must be between 1 and 52.' => 'invalidWeeks',
    'Package rules are invalid.' => 'requiredValue',
    'Package task rules are invalid.' => 'requiredValue',
    'A title and a valid identifier are required.' => 'invalidActivityTitle',
    _ => 'genericError',
  };
  return context.plannerText(key);
}
