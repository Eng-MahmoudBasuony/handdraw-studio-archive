import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_studio/features/cache_management/application/cache_cleanup_cubit.dart';
import 'package:handdraw_studio/features/cache_management/infrastructure/app_cache_service.dart';

Future<void> showCacheCleanupDialog(
  BuildContext context, {
  AppCacheService? service,
}) => showDialog<void>(
  context: context,
  builder: (context) => BlocProvider(
    create: (_) => CacheCleanupCubit(service ?? AppCacheService()),
    child: const _CacheCleanupDialog(),
  ),
);

class _CacheCleanupDialog extends StatelessWidget {
  const _CacheCleanupDialog();
  @override
  Widget build(BuildContext context) {
    String t(String en, String ar) =>
        Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
    return BlocBuilder<CacheCleanupCubit, CacheCleanupState>(
      builder: (context, state) => AlertDialog(
        title: Text(t('Clear cache', 'مسح الكاش')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(
                  'Clear display caches and unused temporary sessions older than 24 hours. Projects, original images, hand library and active files are preserved.',
                  'مسح كاش العرض وملفات الجلسات المؤقتة غير المستخدمة الأقدم من 24 ساعة. تظل المشاريع والصور الأصلية ومكتبة الإيد والملفات المستخدمة محفوظة.',
                ),
              ),
              const SizedBox(height: 16),
              if (state.busy) const LinearProgressIndicator(),
              if (state.result case final result?)
                Text(
                  t(
                    'Display cache cleared. Removed ${result.removedSessions} old temporary sessions.${result.failedRoots > 0 ? ' Some folders could not be cleaned.' : ''}',
                    'تم مسح كاش العرض وحذف ${result.removedSessions} من الجلسات المؤقتة القديمة.${result.failedRoots > 0 ? ' تعذر تنظيف بعض المجلدات.' : ''}',
                  ),
                ),
              if (state.failed)
                Text(
                  t(
                    'Cleanup could not finish. You can retry.',
                    'تعذر إكمال التنظيف. يمكنك المحاولة مرة أخرى.',
                  ),
                ),
              if (!state.busy)
                Text(
                  t(
                    'The next preview may take longer while caches rebuild.',
                    'قد تستغرق أول معاينة بعد المسح وقتًا أطول لإعادة تجهيز الكاش.',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Close', 'إغلاق')),
          ),
          FilledButton.icon(
            key: const ValueKey('clear-cache-now'),
            onPressed: state.busy
                ? null
                : context.read<CacheCleanupCubit>().clear,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(t('Clear cache', 'مسح الكاش')),
          ),
        ],
      ),
    );
  }
}
