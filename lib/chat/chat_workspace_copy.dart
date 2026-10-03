/// Copy for the creation workspace, driven by KORLIX's language selection.
/// Product names and API option values are deliberately kept unchanged.
class KorlixChatCopy {
  KorlixChatCopy(String languageCode)
    : languageCode = languageCode
          .toLowerCase()
          .replaceAll('_', '-')
          .split('-')
          .first;

  final String languageCode;

  String _pick(String english, String spanish, String french) =>
      switch (languageCode) {
        'es' => spanish,
        'fr' => french,
        _ => english,
      };

  String get createTitle => _pick(
    'What would you like to create?',
    '¿Qué te gustaría crear?',
    'Que souhaitez-vous créer ?',
  );
  String get createSubtitle => _pick(
    'Ask a question, work through an idea, or make a picture.',
    'Haz una pregunta, desarrolla una idea o crea una imagen.',
    'Posez une question, explorez une idée ou créez une image.',
  );
  String get helpWrite =>
      _pick('Help me write', 'Ayúdame a escribir', 'Aidez-moi à écrire');
  String get helpWritePrompt =>
      _pick('Help me write ', 'Ayúdame a escribir ', 'Aidez-moi à écrire ');
  String get exploreIdea =>
      _pick('Explore an idea', 'Explorar una idea', 'Explorer une idée');
  String get exploreIdeaPrompt => _pick(
    'Help me think through ',
    'Ayúdame a desarrollar ',
    'Aidez-moi à réfléchir à ',
  );
  String get createPicture =>
      _pick('Create a picture', 'Crear una imagen', 'Créer une image');
  String get thinking => _pick(
    'Thinking through your request…',
    'Analizando tu solicitud…',
    'Analyse de votre demande…',
  );
  String get deleteQuestion => _pick(
    'Delete your question',
    'Eliminar tu pregunta',
    'Supprimer votre question',
  );
  String get deleteAnswer => _pick(
    'Delete this answer',
    'Eliminar esta respuesta',
    'Supprimer cette réponse',
  );
  String get answerCopied =>
      _pick('Answer copied', 'Respuesta copiada', 'Réponse copiée');
  String get copy => _pick('Copy', 'Copiar', 'Copier');
  String get openImage => _pick('Open image', 'Abrir imagen', 'Ouvrir l’image');
  String get saveImage =>
      _pick('Save image', 'Guardar imagen', 'Enregistrer l’image');
  String get chat => _pick('Chat', 'Conversar', 'Discuter');
  String get createImage =>
      _pick('Create image', 'Crear imagen', 'Créer une image');
  String get imageQuality => _pick(
    'Extra-high image quality',
    'Calidad de imagen extra alta',
    'Qualité d’image très élevée',
  );
  String get chatQuality =>
      _pick('Astra · Extra high', 'Astra · Extra alta', 'Astra · Très élevée');
  String get shape => _pick('Shape', 'Formato', 'Format');
  String get square => _pick('Square', 'Cuadrado', 'Carré');
  String get portrait => _pick('Portrait', 'Vertical', 'Portrait');
  String get landscape => _pick('Landscape', 'Horizontal', 'Paysage');
  String get automatic => _pick('Automatic', 'Automático', 'Automatique');
  String get style => _pick('Style', 'Estilo', 'Style');
  String get followPrompt => _pick(
    'Follow my prompt',
    'Seguir mis indicaciones',
    'Suivre mes instructions',
  );
  String get photographic =>
      _pick('Photographic', 'Fotográfico', 'Photographique');
  String get illustration =>
      _pick('Illustration', 'Ilustración', 'Illustration');
  String get graphicDesign =>
      _pick('Graphic design', 'Diseño gráfico', 'Graphisme');
  String get cinematic =>
      _pick('Cinematic', 'Cinematográfico', 'Cinématographique');
  String get imageGuidance => _pick(
    'Describe the subject, setting, lighting, and any exact words to include.',
    'Describe el tema, el entorno, la iluminación y las palabras exactas que quieras incluir.',
    'Décrivez le sujet, le décor, l’éclairage et les mots exacts à inclure.',
  );
  String get textHint => _pick(
    'Ask anything, or describe what you want to create…',
    'Pregunta lo que quieras o describe lo que quieres crear…',
    'Posez une question ou décrivez ce que vous souhaitez créer…',
  );
  String get imageHint => _pick(
    'Describe the picture you want…',
    'Describe la imagen que quieres…',
    'Décrivez l’image que vous souhaitez…',
  );
  String get send => _pick('Send', 'Enviar', 'Envoyer');
  String get sending => _pick('Sending', 'Enviando', 'Envoi en cours');
  String get openImagineStudio => _pick(
    'Open Imagine Studio',
    'Abrir Imagine Studio',
    'Ouvrir Imagine Studio',
  );
  String get imagineStudioSubtitle => _pick(
    'Explore styles, creative briefs & your gallery',
    'Explora estilos, ideas creativas y tu galería',
    'Explorez les styles, les projets créatifs et votre galerie',
  );
  String get thinkingStatus => _pick(
    'Thinking deeply and preparing your answer…',
    'Analizando tu solicitud y preparando tu respuesta…',
    'Analyse approfondie et préparation de votre réponse…',
  );
  String get creatingImageStatus => _pick(
    'Creating your picture with extra detail. This may take a few minutes…',
    'Creando tu imagen con gran detalle. Esto puede tardar unos minutos…',
    'Création de votre image avec un maximum de détails. Cela peut prendre quelques minutes…',
  );
  String get picturePromptRequired => _pick(
    'Describe the picture you want Korlix AI to create.',
    'Describe la imagen que quieres que Korlix AI cree.',
    'Décrivez l’image que vous souhaitez que Korlix AI crée.',
  );
  String get imageGenerated =>
      _pick('Image generated.', 'Imagen generada.', 'Image créée.');
  String get yourPicture => _pick('Your picture', 'Tu imagen', 'Votre image');
  String get noImageReturned => _pick(
    'No image was returned.',
    'No se recibió ninguna imagen.',
    'Aucune image n’a été reçue.',
  );
}
