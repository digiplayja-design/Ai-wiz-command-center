import 'package:flutter/material.dart';

enum ImproveGender { female, male }

class ImproveTemplate {
  const ImproveTemplate({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.variations,
  });

  final String id;
  final String name;
  final IconData icon;
  final String description;
  final List<String> variations;
}

const List<ImproveTemplate> kImprovePictureTemplates = [
  ImproveTemplate(
    id: 'cartoon',
    name: 'Cartoon',
    icon: Icons.brush_rounded,
    description: 'Stylized cartoon portrait.',
    variations: ['Soft Cartoon', 'Studio Cartoon', 'Premium Cartoon'],
  ),
  ImproveTemplate(
    id: 'caricature',
    name: 'Caricature',
    icon: Icons.tag_faces_rounded,
    description: 'Playful exaggerated portrait.',
    variations: ['Soft Exaggeration', 'Comedy Look', 'Bold Caricature'],
  ),
  ImproveTemplate(
    id: 'gothic',
    name: 'Gothic',
    icon: Icons.dark_mode_rounded,
    description:
        'Gothic fashion, makeup, mood and lighting while preserving identity.',
    variations: ['Dark Royal', 'Cathedral Noir', 'Luxury Gothic'],
  ),
  ImproveTemplate(
    id: 'mirror',
    name: 'Mirror',
    icon: Icons.flip_rounded,
    description: 'Realistic mirror reflection looking back at you.',
    variations: ['Classic Mirror', 'Royal Mirror', 'Cinematic Mirror'],
  ),
  ImproveTemplate(
    id: 'smoky',
    name: 'Smoky',
    icon: Icons.cloud_rounded,
    description: 'Premium smoke aura with cinematic curves and depth.',
    variations: ['Silver Smoke', 'Blue Aura', 'Shadow Smoke'],
  ),
  ImproveTemplate(
    id: 'smooth',
    name: 'Smooth',
    icon: Icons.auto_fix_high_rounded,
    description: 'Clean HD enhancement with natural skin detail.',
    variations: ['Natural Smooth', 'Studio Smooth', 'Glow Smooth'],
  ),
  ImproveTemplate(
    id: 'fiery',
    name: 'Fiery',
    icon: Icons.local_fire_department_rounded,
    description: '3D fire glow, embers and dramatic rim lighting.',
    variations: ['Ember', 'Inferno', 'Phoenix'],
  ),
  ImproveTemplate(
    id: 'wet',
    name: 'Wet',
    icon: Icons.water_drop_rounded,
    description: 'Rain, water detail and cinematic wet-look finish.',
    variations: ['Rain Portrait', 'Gloss Wet', 'Storm Wet'],
  ),
  ImproveTemplate(
    id: 'white',
    name: 'White',
    icon: Icons.face_retouching_natural_rounded,
    description:
        'Race transformation preview while preserving core facial identity.',
    variations: ['Natural White', 'Editorial White', 'Soft White'],
  ),
  ImproveTemplate(
    id: 'black',
    name: 'Black',
    icon: Icons.face_6_rounded,
    description:
        'Race transformation preview while preserving core facial identity.',
    variations: ['Natural Black', 'Editorial Black', 'Soft Black'],
  ),
  ImproveTemplate(
    id: 'asian',
    name: 'Asian',
    icon: Icons.face_5_rounded,
    description:
        'Race transformation preview while preserving core facial identity.',
    variations: ['Natural Asian', 'Editorial Asian', 'Soft Asian'],
  ),
  ImproveTemplate(
    id: 'mask',
    name: 'Mask',
    icon: Icons.theater_comedy_rounded,
    description: 'Elegant luxury mask looks with couture detail.',
    variations: ['Royal Gold', 'Black Luxury', 'Crystal Venetian'],
  ),
];
