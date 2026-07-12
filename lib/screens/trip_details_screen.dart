import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TripDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> trip;

  const TripDetailsScreen({super.key, required this.trip});

  Future<void> _makeCall(String number) async {
    if (number.isEmpty) return;
    final Uri url = Uri.parse('tel:$number');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tripName = trip['name'] ?? 'Trip Details';
    final orgName = trip['organization'] ?? 'N/A';
    final vehicle = trip['vehicle'] as Map<String, dynamic>?;
    final driver = trip['driver'] as Map<String, dynamic>?;
    final assistant = trip['assistant'] as Map<String, dynamic>?;
    final stops = (trip['stops'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tripName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Trip Summary Header Card
            Card(
              elevation: 3,
              shadowColor: theme.colorScheme.shadow.withOpacity(0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            orgName,
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Active Service',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    
                    // Vehicle details
                    Row(
                      children: [
                        Icon(Icons.directions_bus_rounded, color: Colors.blue.shade300, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Vehicle Description', style: TextStyle(color: Colors.grey, fontSize: 11)),
                              Text(
                                vehicle != null 
                                    ? '${vehicle['registration_number'] ?? 'N/A'} (${vehicle['model'] ?? 'N/A'})'
                                    : 'N/A',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Crew Info (Driver & Attendant)
                    Row(
                      children: [
                        // Driver
                        if (driver != null)
                          Expanded(
                            child: Row(
                              children: [
                                Icon(Icons.badge_rounded, color: Colors.teal.shade300, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Driver', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                      Text(
                                        driver['name'] ?? 'N/A',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (driver['mobile'] != null && driver['mobile'].toString().isNotEmpty)
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.phone_rounded, color: Colors.teal, size: 18),
                                    onPressed: () => _makeCall(driver['mobile'].toString()),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(width: 8),
                        // Attendant/Assistant
                        if (assistant != null)
                          Expanded(
                            child: Row(
                              children: [
                                Icon(Icons.support_agent_rounded, color: Colors.orange.shade300, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Attendant', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                      Text(
                                        assistant['name'] ?? 'N/A',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (assistant['mobile'] != null && assistant['mobile'].toString().isNotEmpty)
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.phone_rounded, color: Colors.teal, size: 18),
                                    onPressed: () => _makeCall(assistant['mobile'].toString()),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Section Title
            Row(
              children: [
                Icon(Icons.timeline_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Stops & Enrolled Children',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Timeline List of Stops
            if (stops.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text('No stops found for this route.', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: stops.length,
                itemBuilder: (context, index) {
                  final stop = stops[index];
                  final stopName = stop['name'] ?? 'N/A';
                  final stopTime = stop['time'] ?? 'N/A';
                  final displayTime = stopTime.toString().split(':').take(2).join(':');
                  final children = (stop['children'] as List?) ?? [];

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Timeline indicator
                        Column(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: index == 0 ? theme.colorScheme.primary : theme.colorScheme.secondary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.shadow.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                            ),
                            Expanded(
                              child: Container(
                                width: 2,
                                color: index == stops.length - 1 
                                    ? Colors.transparent 
                                    : Colors.grey.shade300,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        // Stop content
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Stop Name & Scheduled Time Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        stopName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      displayTime,
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Children List at this Stop
                                if (children.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                                    child: Text(
                                      'No children enrolled for this stop.',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  )
                                else
                                  ...children.map((dynamic child) {
                                    final childName = child['name'] ?? 'N/A';
                                    final status = child['status'] ?? 'N/A';
                                    final grade = child['grade'] ?? 'N/A';
                                    final division = child['division'] ?? 'N/A';
                                    final isPickup = child['is_pickup'] == true;
                                    final isDrop = child['is_drop'] == true;

                                    // Color coding status
                                    Color statusBgColor = Colors.grey.shade100;
                                    Color statusTextColor = Colors.grey.shade600;
                                    if (status.toString().toLowerCase() == 'active') {
                                      statusBgColor = Colors.green.withOpacity(0.1);
                                      statusTextColor = Colors.green.shade700;
                                    } else if (status.toString().toLowerCase() == 'pending') {
                                      statusBgColor = Colors.orange.withOpacity(0.1);
                                      statusTextColor = Colors.orange.shade700;
                                    } else if (status.toString().toLowerCase() == 'hold' || status.toString().toLowerCase() == 'pending_hold') {
                                      statusBgColor = Colors.red.withOpacity(0.1);
                                      statusTextColor = Colors.red.shade700;
                                    }

                                    return Container(
                                      margin: const EdgeInsets.only(top: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor: theme.colorScheme.secondaryContainer,
                                            child: Icon(
                                              Icons.person_rounded,
                                              size: 16,
                                              color: theme.colorScheme.onSecondaryContainer,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  childName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Grade: $grade - Div: $division',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              // Status badge
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: statusBgColor,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  status.toString().toUpperCase(),
                                                  style: TextStyle(
                                                    color: statusTextColor,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              // Stop Type (Pickup/Drop) Badge
                                              if (isPickup)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Text(
                                                    'PICKUP',
                                                    style: TextStyle(
                                                      color: Colors.blue,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 8,
                                                    ),
                                                  ),
                                                )
                                              else if (isDrop)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.purple.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Text(
                                                    'DROP',
                                                    style: TextStyle(
                                                      color: Colors.purple,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 8,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
