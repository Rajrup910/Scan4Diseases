import 'package:flutter/material.dart';

import '../../services/sound_service.dart';
import '../../services/theme_service.dart';
import '../Appointments/appointmentsScreen.dart';
import '../theme.dart';

class DoctorProfileData {
  final int id;
  final String name;
  final String email;
  final String regNo;
  final String council;
  final String designation;
  final String qualifications;
  final String hospital;
  final String experience;
  final double rating;
  final int reviewCount;
  final List<String> specialties;
  final String timings;
  final String bio;

  const DoctorProfileData({
    required this.id,
    required this.name,
    required this.email,
    required this.regNo,
    required this.council,
    required this.designation,
    required this.qualifications,
    required this.hospital,
    required this.experience,
    required this.rating,
    required this.reviewCount,
    required this.specialties,
    required this.timings,
    required this.bio,
  });
}

class KnowYourDoctorScreen extends StatefulWidget {
  const KnowYourDoctorScreen({super.key});

  @override
  State<KnowYourDoctorScreen> createState() => _KnowYourDoctorScreenState();
}

class _KnowYourDoctorScreenState extends State<KnowYourDoctorScreen> {
  String _selectedFilter = 'All';
  int? _expandedDoctorId;

  static const List<DoctorProfileData> _doctors = [
    DoctorProfileData(
      id: 1,
      name: 'Dr. A. Rao',
      email: 'dr.rao@example.com',
      regNo: 'MH-12345',
      council: 'Maharashtra Medical Council / NMC',
      designation: 'Senior Consultant Dermatologist & Dermatosurgeon',
      qualifications: 'MBBS, MD (Dermatology, Venereology & Leprosy), DNB',
      hospital: 'Apollo Dermatology Centre, Mumbai',
      experience: '14+ years',
      rating: 4.9,
      reviewCount: 1420,
      specialties: ['Pigmented Lesions', 'Melanoma Screening', 'Mohs Surgery', 'Dermoscopy'],
      timings: 'Mon – Sat · 09:00 – 18:00 IST',
      bio: 'Pioneered early cutaneous melanoma screening algorithms and high-resolution dermatosurgical triage across premier Indian tertiary institutions.',
    ),
    DoctorProfileData(
      id: 2,
      name: 'Dr. Sunita Mehta',
      email: 'dr.mehta@example.com',
      regNo: 'KA-67890',
      council: 'Karnataka Medical Council',
      designation: 'Consultant Dermatologist & Cutaneous Oncologist',
      qualifications: 'MBBS, MD (Dermatology), Fellowship in Dermato-Oncology (TMH)',
      hospital: 'Manipal Skin & Oncology Clinic, Bengaluru',
      experience: '11+ years',
      rating: 4.8,
      reviewCount: 980,
      specialties: ['Basal Cell Carcinoma', 'Actinic Keratosis', 'Cryotherapy', 'Immunotherapy'],
      timings: 'Mon – Fri · 10:00 – 17:00 IST',
      bio: 'Specialist in non-melanoma skin cancer management, photo-damage mitigation, and computer-assisted lesion boundary assessment.',
    ),
    DoctorProfileData(
      id: 3,
      name: 'Dr. Vikram Kapoor',
      email: 'dr.kapoor@example.com',
      regNo: 'DL-98765',
      council: 'Delhi Medical Council',
      designation: 'Associate Director of Dermatology & Laser Medicine',
      qualifications: 'MBBS, MD, MNAMS, Fellow American Academy of Dermatology (FAAD)',
      hospital: 'Max Super Speciality Skin Centre, New Delhi',
      experience: '16+ years',
      rating: 4.9,
      reviewCount: 1850,
      specialties: ['Squamous Cell Carcinoma', 'Dermato-Pathology', 'Precancerous Lesions'],
      timings: 'Tue – Sun · 09:30 – 16:30 IST',
      bio: 'Nationally recognized authority in histopathologic lesion correlation, precancerous lesion eradication, and evidence-grounded tele-dermatology.',
    ),
    DoctorProfileData(
      id: 4,
      name: 'Dr. Priya Nambiar',
      email: 'dr.nambiar@example.com',
      regNo: 'KL-45678',
      council: 'Travancore-Cochin Medical Council',
      designation: 'Clinical Specialist in Adult & Pediatric Dermatology',
      qualifications: 'MBBS, MD (DVL), DNB Dermatology',
      hospital: 'Amrita Institute of Dermatology, Kochi',
      experience: '9+ years',
      rating: 4.9,
      reviewCount: 860,
      specialties: ['Benign Nevi', 'Atypical Moles', 'Seborrheic Keratosis', 'Phototherapy'],
      timings: 'Mon – Sat · 10:00 – 16:00 IST',
      bio: 'Dedicated to long-term mole mapping, longitudinal surveillance of dysplastic nevi, and patient education on sun safety.',
    ),
    DoctorProfileData(
      id: 5,
      name: 'Dr. Rajesh Deshmukh',
      email: 'dr.deshmukh@example.com',
      regNo: 'MH-54321',
      council: 'Maharashtra Medical Council',
      designation: 'Consultant Dermatologist & Aesthetic Surgeon',
      qualifications: 'MBBS, DVD, FCPS Dermatology',
      hospital: 'Ruby Hall Clinic Dermatology Dept, Pune',
      experience: '13+ years',
      rating: 4.8,
      reviewCount: 1120,
      specialties: ['Dermatofibroma', 'Vascular Lesions', 'Laser Excision'],
      timings: 'Mon – Fri · 09:00 – 17:30 IST',
      bio: 'Expertise in minimally invasive biopsy techniques, scar revision, and comprehensive evaluation of atypical vascular lesions.',
    ),
    DoctorProfileData(
      id: 6,
      name: 'Dr. Ananya Sen',
      email: 'dr.sen@example.com',
      regNo: 'WB-34567',
      council: 'West Bengal Medical Council',
      designation: 'Senior Registrar & Dermato-Epidemiologist',
      qualifications: 'MBBS, MD Dermatology (PGIMER), MRCP (SCE Derm, UK)',
      hospital: 'Medica Superspecialty Skin Institute, Kolkata',
      experience: '10+ years',
      rating: 4.9,
      reviewCount: 920,
      specialties: ['Pigmentary Disorders', 'Melanoma Risk Profiling', 'Tele-Dermatology'],
      timings: 'Mon – Sat · 11:00 – 19:00 IST',
      bio: 'Pioneered digital skin risk profiling in South Asia with published clinical research on early melanoma markers in skin of colour.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.mode,
      builder: (_, __, ___) {
        final dark = ThemeService.instance.isDark(context);
        final ink = dark ? Themes.darkInk : Themes.ink;
        final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
        final accent = dark ? Themes.tealLight : Themes.brand;

        final filtered = _selectedFilter == 'All'
            ? _doctors
            : _doctors
                .where((d) => d.specialties.any((s) =>
                    s.toLowerCase().contains(_selectedFilter.toLowerCase())))
                .toList();

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: dark
                          ? [
                              const Color(0xFF0F1B18),
                              const Color(0xFF0F1117),
                              const Color(0xFF161920),
                            ]
                          : [
                              const Color(0xFFE6F3EF),
                              const Color(0xFFF4F6F9),
                              Colors.white,
                            ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                InkWell(
                                  onTap: () {
                                    SoundService.instance.tap();
                                    Navigator.pop(context);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: dark
                                        ? Themes.liquidGlassDecoration(
                                            radius: 12, dark: true)
                                        : Themes.liquidGlassDecoration(
                                            radius: 12),
                                    child: Icon(Icons.arrow_back_rounded,
                                        color: ink, size: 20),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Themes.sectionHeaderPill(
                                    'Know Your Doctor',
                                    dark: dark,
                                    icon: Icons.verified_user_rounded,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Verified Clinical Specialists',
                              style: TextStyle(
                                color: ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                shadows:
                                    dark ? Themes.onMediaDark : Themes.onMedia,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'All doctors on Scan4Disease are verified dermatologists registered with State Medical Councils and the National Medical Commission.',
                              style: TextStyle(
                                color: inkSoft,
                                fontSize: 13.5,
                                height: 1.4,
                                shadows:
                                    dark ? Themes.onMediaDark : Themes.onMedia,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildTrustBanner(dark, accent),
                            const SizedBox(height: 16),
                            _buildFilterChips(dark, accent),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final doc = filtered[index];
                            final isExpanded = _expandedDoctorId == doc.id;
                            return _buildDoctorCard(context, doc, dark, ink,
                                inkSoft, accent, isExpanded);
                          },
                          childCount: filtered.length,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrustBanner(bool dark, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: dark
          ? Themes.liquidGlassDecoration(
              radius: 16, dark: true, topAlpha: 0.85, bottomAlpha: 0.70)
          : Themes.liquidGlassDecoration(radius: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Icon(Icons.shield_outlined, color: accent, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '100% Medical Council Verified',
                  style: TextStyle(
                    color: dark ? Themes.darkInk : Themes.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Independent verification of credentials & active hospital affiliations.',
                  style: TextStyle(
                    color: dark ? Themes.darkInkSoft : Themes.inkSoft,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(bool dark, Color accent) {
    final filters = ['All', 'Melanoma', 'Carcinoma', 'Nevus', 'Laser'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSel = _selectedFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                SoundService.instance.tap();
                setState(() => _selectedFilter = f);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSel
                      ? accent.withValues(alpha: 0.20)
                      : (dark
                          ? const Color(0xFF161B24)
                          : Colors.white.withValues(alpha: 0.75)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSel
                        ? accent
                        : (dark
                            ? Themes.darkBorder
                            : Colors.white.withValues(alpha: 0.85)),
                    width: isSel ? 1.4 : 1.0,
                  ),
                ),
                child: Text(
                  f == 'All' ? 'All Specialists' : f,
                  style: TextStyle(
                    color: isSel
                        ? accent
                        : (dark ? Themes.darkInkSoft : Themes.inkSoft),
                    fontSize: 12.5,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDoctorCard(
    BuildContext context,
    DoctorProfileData doc,
    bool dark,
    Color ink,
    Color inkSoft,
    Color accent,
    bool isExpanded,
  ) {
    final tile =
        dark ? Themes.darkBrandTint : Themes.brandTint.withValues(alpha: 0.70);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: dark
          ? Themes.liquidGlassDecoration(
              radius: 18, dark: true, topAlpha: 0.88, bottomAlpha: 0.74)
          : Themes.liquidGlassDecoration(radius: 18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            SoundService.instance.tap();
            setState(() {
              _expandedDoctorId = isExpanded ? null : doc.id;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.28),
                            accent.withValues(alpha: 0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          doc.name
                              .replaceFirst('Dr. ', '')
                              .split(' ')
                              .map((p) => p.isNotEmpty ? p[0] : '')
                              .take(2)
                              .join(),
                          style: TextStyle(
                            color: accent,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  doc.name,
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Themes.routine.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: Themes.routine
                                          .withValues(alpha: 0.35)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded,
                                        color: Themes.routine, size: 11),
                                    SizedBox(width: 3),
                                    Text(
                                      'VERIFIED',
                                      style: TextStyle(
                                        color: Themes.routine,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            doc.designation,
                            style: TextStyle(
                              color: inkSoft,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Color(0xFFEAB308), size: 15),
                              const SizedBox(width: 3),
                              Text(
                                '${doc.rating}',
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '(${doc.reviewCount}+)',
                                style: TextStyle(
                                  color: inkSoft,
                                  fontSize: 11.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                  width: 3,
                                  height: 3,
                                  decoration: BoxDecoration(
                                      color: inkSoft, shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Icon(Icons.work_outline_rounded,
                                  size: 13, color: inkSoft),
                              const SizedBox(width: 3),
                              Text(
                                doc.experience,
                                style: TextStyle(
                                  color: inkSoft,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: inkSoft,
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: doc.specialties.map((s) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: tile,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: dark
                              ? Themes.tealGlow.withValues(alpha: 0.20)
                              : Colors.white.withValues(alpha: 0.70),
                        ),
                      ),
                      child: Text(
                        s,
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (isExpanded) ...[
                  const SizedBox(height: 14),
                  Divider(
                      height: 1,
                      color: dark ? Themes.darkBorder : Themes.borderSubtle),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.badge_outlined,
                    'Registration Number',
                    '${doc.regNo} · ${doc.council}',
                    dark,
                    ink,
                    inkSoft,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    Icons.school_outlined,
                    'Qualifications',
                    doc.qualifications,
                    dark,
                    ink,
                    inkSoft,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    Icons.local_hospital_outlined,
                    'Hospital Affiliation',
                    doc.hospital,
                    dark,
                    ink,
                    inkSoft,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    Icons.access_time_rounded,
                    'Consultation Slots',
                    doc.timings,
                    dark,
                    ink,
                    inkSoft,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    doc.bio,
                    style: TextStyle(
                      color: inkSoft,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            SoundService.instance.open();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AppointmentsScreen()),
                            );
                          },
                          icon: const Icon(Icons.calendar_month_rounded,
                              size: 16),
                          label: const Text('Book Visit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Themes.brand,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value,
    bool dark,
    Color ink,
    Color inkSoft,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: dark ? Themes.tealLight : Themes.brand),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 12, height: 1.35, color: ink),
              children: [
                TextSpan(
                  text: '$label: ',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, color: inkSoft),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(fontWeight: FontWeight.w600, color: ink),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
