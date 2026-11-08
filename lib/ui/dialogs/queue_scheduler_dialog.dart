import 'package:flutter/material.dart';
import '../../services/download_manager.dart';

Future<void> showQueueSchedulerDialog(
  BuildContext context,
  DownloadManager manager,
) async {
  var selectedQueue = manager.namedQueues.first;
  var schedule = manager.getQueueSchedule(selectedQueue);
  var startHour = schedule?.startHour ?? 2;
  var startMinute = schedule?.startMinute ?? 0;
  var stopHour = schedule?.stopHour ?? 6;
  var stopMinute = schedule?.stopMinute ?? 0;
  var isEnabled = schedule?.isEnabled ?? false;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.schedule, size: 20),
            SizedBox(width: 8),
            Text('Queue Scheduler'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedQueue,
              decoration: const InputDecoration(labelText: 'Named Queue'),
              items: manager.namedQueues
                  .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setDialogState(() {
                    selectedQueue = val;
                    final s = manager.getQueueSchedule(val);
                    startHour = s?.startHour ?? 2;
                    startMinute = s?.startMinute ?? 0;
                    stopHour = s?.stopHour ?? 6;
                    stopMinute = s?.stopMinute ?? 0;
                    isEnabled = s?.isEnabled ?? false;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Enable Auto Schedule',
                style: TextStyle(fontSize: 13),
              ),
              value: isEnabled,
              onChanged: (val) => setDialogState(() => isEnabled = val),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.play_arrow_outlined,
                color: Color(0xFF15803D),
              ),
              title: const Text('Start Time', style: TextStyle(fontSize: 13)),
              trailing: TextButton(
                child: Text(
                  '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}',
                ),
                onPressed: () async {
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay(
                      hour: startHour,
                      minute: startMinute,
                    ),
                  );
                  if (t != null) {
                    setDialogState(() {
                      startHour = t.hour;
                      startMinute = t.minute;
                    });
                  }
                },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.stop_outlined,
                color: Color(0xFFDC2626),
              ),
              title: const Text('Stop Time', style: TextStyle(fontSize: 13)),
              trailing: TextButton(
                child: Text(
                  '${stopHour.toString().padLeft(2, '0')}:${stopMinute.toString().padLeft(2, '0')}',
                ),
                onPressed: () async {
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay(hour: stopHour, minute: stopMinute),
                  );
                  if (t != null) {
                    setDialogState(() {
                      stopHour = t.hour;
                      stopMinute = t.minute;
                    });
                  }
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              manager.setQueueSchedule(
                QueueSchedule(
                  queueName: selectedQueue,
                  startHour: startHour,
                  startMinute: startMinute,
                  stopHour: stopHour,
                  stopMinute: stopMinute,
                  isEnabled: isEnabled,
                ),
              );
              Navigator.of(dialogCtx).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Schedule updated for "$selectedQueue"'),
                  ),
                );
              }
            },
            child: const Text('Save Schedule'),
          ),
        ],
      ),
    ),
  );
}
