// Level Up — Based on Streak by InlitX. GPL-3.0-only.
import 'planner_models.dart';

/// Configurable, reusable definitions. Merely browsing never starts a package.
final levelUpChallengeCatalog = List<ChallengeTemplate>.unmodifiable([
  ChallengeTemplate(
    id: 'steady-start',
    name: 'Steady start',
    description:
        'Build a deliberate start to your day with a small, repeatable focus block.',
    difficulty: ChallengeDifficulty.easy,
    durationDays: 3,
    completionXp: 30,
    createdAt: DateTime(2026, 10, 29),
    updatedAt: DateTime(2026, 10, 29),
    tasks: const [
      ChallengeTaskDefinition(
        id: 'focus',
        title: 'A focused start',
        dayOffsets: [0, 1, 2],
        startMinute: 9 * 60,
        durationMinutes: 20,
        rewardXp: 10,
        skipPenalty: 5,
        steps: [
          'Choose one priority',
          'Focus for 15 minutes',
          'Write the next action',
        ],
      ),
    ],
  ),
  ChallengeTemplate(
    id: 'study-rhythm',
    name: 'Study rhythm',
    description:
        'One week of focused study, followed by a short review. Your existing commitments stay in place.',
    difficulty: ChallengeDifficulty.medium,
    durationDays: 7,
    completionXp: 100,
    createdAt: DateTime(2026, 10, 29),
    updatedAt: DateTime(2026, 10, 29),
    tasks: const [
      ChallengeTaskDefinition(
        id: 'study',
        title: 'Deep study',
        dayOffsets: [0, 1, 2, 3, 4, 5, 6],
        startMinute: 19 * 60,
        durationMinutes: 60,
        target: 60,
        unit: 'minutes',
        rewardXp: 20,
        skipPenalty: 10,
      ),
      ChallengeTaskDefinition(
        id: 'review',
        title: 'Recall and review',
        dayOffsets: [0, 1, 2, 3, 4, 5, 6],
        startMinute: 20 * 60,
        durationMinutes: 15,
        dependencies: ['study'],
        steps: ['Recall the key ideas', 'Record a question for tomorrow'],
        rewardXp: 10,
        skipPenalty: 10,
      ),
    ],
  ),
  ChallengeTemplate(
    id: 'fitness-foundation',
    name: 'Fitness foundation',
    description:
        'A demanding week of planned movement and recovery. Choose an appropriate exercise intensity for yourself.',
    difficulty: ChallengeDifficulty.hard,
    durationDays: 7,
    completionXp: 180,
    createdAt: DateTime(2026, 10, 29),
    updatedAt: DateTime(2026, 10, 29),
    tasks: const [
      ChallengeTaskDefinition(
        id: 'workout',
        title: 'Workout sequence',
        dayOffsets: [0, 2, 4, 6],
        startMinute: 15 * 60,
        durationMinutes: 90,
        steps: [
          'Warm up',
          'Complete your planned workout',
          'Cool down',
          'Record the session',
        ],
        rewardXp: 40,
        skipPenalty: 25,
      ),
      ChallengeTaskDefinition(
        id: 'recover',
        title: 'Recovery and mobility',
        dayOffsets: [0, 1, 2, 3, 4, 5, 6],
        startMinute: 16 * 60 + 30,
        durationMinutes: 15,
        target: 15,
        unit: 'minutes',
        rewardXp: 15,
        skipPenalty: 15,
      ),
    ],
  ),
]);
