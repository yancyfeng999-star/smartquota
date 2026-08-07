import Foundation
import Observation

/// Runtime localization for 智额 UI. Default language: Simplified Chinese.
@MainActor
@Observable
final class L10n {
    static let shared = L10n()

    /// Bumps when language changes so SwiftUI can refresh.
    private(set) var revision: Int = 0

    var language: AppLanguage = .zhHans {
        didSet {
            if oldValue != language { revision &+= 1 }
        }
    }

    private init() {}

    func t(_ key: String) -> String {
        Self.lookup(key, language: language)
    }

    func tf(_ key: String, _ args: CVarArg...) -> String {
        let format = t(key)
        return String(format: format, locale: language.locale, arguments: args)
    }

    static func lookup(_ key: String, language: AppLanguage) -> String {
        if let row = table[key] {
            if let v = row[language], !v.isEmpty { return v }
            // Prefer English over Chinese when target lang missing (avoids mixed CN in EN UI).
            if language != .zhHans, let v = row[.en], !v.isEmpty { return v }
            if let v = row[.zhHans], !v.isEmpty { return v }
        }
        return key
    }

    /// Keys missing Simplified Chinese (required) — for DEBUG integrity checks.
    static func keysMissingChinese() -> [String] {
        table.compactMap { key, row in
            guard let v = row[.zhHans], !v.isEmpty else { return key }
            return nil
        }.sorted()
    }

    /// All localization keys currently registered.
    static var allKeys: [String] { Array(table.keys).sorted() }

    /// key → language → string
    private static let table: [String: [AppLanguage: String]] = [
        "app.about": [.zhHans: "智额 SmartQuota · 监控 ChatGPT / Kimi / MiniMax / Grok 等会员额度", .en: "SmartQuota · Monitor ChatGPT / Kimi / MiniMax / Grok and more", .ja: "SmartQuota · ChatGPT / Kimi / MiniMax / Grok などを監視", .ko: "SmartQuota · ChatGPT / Kimi / MiniMax / Grok 등 모니터링", .ru: "SmartQuota · Мониторинг ChatGPT / Kimi / MiniMax / Grok", .ar: "SmartQuota · مراقبة ChatGPT و Kimi و MiniMax و Grok", .fr: "SmartQuota · Suivi ChatGPT / Kimi / MiniMax / Grok", .de: "SmartQuota · Überwacht ChatGPT / Kimi / MiniMax / Grok", .es: "SmartQuota · Monitorea ChatGPT / Kimi / MiniMax / Grok", .pt: "SmartQuota · Monitora ChatGPT / Kimi / MiniMax / Grok"],
        "app.name": [.zhHans: "智额", .en: "SmartQuota", .ja: "智额", .ko: "智额", .ru: "SmartQuota", .ar: "SmartQuota", .fr: "SmartQuota", .de: "SmartQuota", .es: "SmartQuota", .pt: "SmartQuota"],
        "app.tagline": [.zhHans: "会员额度监控", .en: "Membership quota monitor", .ja: "メンバーシップ枠モニター", .ko: "멤버십 한도 모니터", .ru: "Монитор квот подписок", .ar: "مراقب حصص العضوية", .fr: "Suivi des quotas d’abonnement", .de: "Abo-Kontingent-Monitor", .es: "Monitor de cuotas", .pt: "Monitor de cotas"],
        "common.activation": [.zhHans: "开通", .en: "Activated", .ja: "開始日", .ko: "개통일", .ru: "Активация", .ar: "التفعيل", .fr: "Activation", .de: "Aktiviert", .es: "Activación", .pt: "Ativação"],
        "common.back": [.zhHans: "返回", .en: "Back", .ja: "戻る", .ko: "뒤로", .ru: "Назад", .ar: "رجوع", .fr: "Retour", .de: "Zurück", .es: "Atrás", .pt: "Voltar"],
        "common.build": [.zhHans: "构建", .en: "Build", .ja: "ビルド", .ko: "빌드", .ru: "Сборка", .ar: "البناء", .fr: "Build", .de: "Build", .es: "Build", .pt: "Build"],
        "common.cancel": [.zhHans: "取消", .en: "Cancel", .ja: "キャンセル", .ko: "취소", .ru: "Отмена", .ar: "إلغاء", .fr: "Annuler", .de: "Abbrechen", .es: "Cancelar", .pt: "Cancelar"],
        "common.checking": [.zhHans: "检测中…", .en: "Checking…", .ja: "確認中…", .ko: "확인 중…", .ru: "Проверка…", .ar: "جارٍ الفحص…", .fr: "Vérification…", .de: "Prüfen…", .es: "Comprobando…", .pt: "Verificando…"],
        "common.done": [.zhHans: "完成", .en: "Done", .ja: "完了", .ko: "완료", .ru: "Готово", .ar: "تم", .fr: "Terminé", .de: "Fertig", .es: "Listo", .pt: "Concluído"],
        "common.failure": [.zhHans: "失败", .en: "Failed", .ja: "失敗", .ko: "실패", .ru: "Ошибка", .ar: "فشل", .fr: "Échec", .de: "Fehlgeschlagen", .es: "Error", .pt: "Falha"],
        "common.how_to_probe": [.zhHans: "如何检测", .en: "How detection works", .ja: "検出方法", .ko: "감지 방법", .ru: "Как проверяется", .ar: "كيف يعمل الكشف", .fr: "Comment ça marche", .de: "So wird erkannt", .es: "Cómo se detecta", .pt: "Como detectar"],
        "common.no_quota": [.zhHans: "暂无额度数据", .en: "No quota data", .ja: "枠データなし", .ko: "한도 데이터 없음", .ru: "Нет данных квоты", .ar: "لا توجد بيانات حصة", .fr: "Aucune donnée de quota", .de: "Keine Kontingentdaten", .es: "Sin datos de cuota", .pt: "Sem dados de cota"],
        "common.not_tested": [.zhHans: "未检测", .en: "Not tested", .ja: "未確認", .ko: "미확인", .ru: "Не проверено", .ar: "لم يُختبر", .fr: "Non testé", .de: "Nicht geprüft", .es: "Sin probar", .pt: "Não testado"],
        "common.open": [.zhHans: "打开", .en: "Open", .ja: "開く", .ko: "열기", .ru: "Открыть", .ar: "فتح", .fr: "Ouvrir", .de: "Öffnen", .es: "Abrir", .pt: "Abrir"],
        "common.open_site": [.zhHans: "打开官网", .en: "Open website", .ja: "サイトを開く", .ko: "웹사이트 열기", .ru: "Сайт", .ar: "الموقع", .fr: "Site web", .de: "Website", .es: "Sitio web", .pt: "Site"],
        "common.plan": [.zhHans: "套餐", .en: "Plan", .ja: "プラン", .ko: "요금제", .ru: "План", .ar: "الخطة", .fr: "Offre", .de: "Tarif", .es: "Plan", .pt: "Plano"],
        "common.probe_status": [.zhHans: "检测状态", .en: "Status", .ja: "状態", .ko: "상태", .ru: "Статус", .ar: "الحالة", .fr: "État", .de: "Status", .es: "Estado", .pt: "Status"],
        "common.quit": [.zhHans: "退出应用", .en: "Quit App", .ja: "アプリ終了", .ko: "앱 종료", .ru: "Выход", .ar: "خروج", .fr: "Quitter l’app", .de: "App beenden", .es: "Salir de la app", .pt: "Sair do app"],
        "common.refreshing": [.zhHans: "正在刷新…", .en: "Refreshing…", .ja: "更新中…", .ko: "새로고침 중…", .ru: "Обновление…", .ar: "جارٍ التحديث…", .fr: "Actualisation…", .de: "Aktualisieren…", .es: "Actualizando…", .pt: "Atualizando…"],
        "common.save": [.zhHans: "保存", .en: "Save", .ja: "保存", .ko: "저장", .ru: "Сохранить", .ar: "حفظ", .fr: "Enregistrer", .de: "Speichern", .es: "Guardar", .pt: "Salvar"],
        "common.settings": [.zhHans: "设置", .en: "Settings", .ja: "設定", .ko: "설정", .ru: "Настройки", .ar: "الإعدادات", .fr: "Réglages", .de: "Einstellungen", .es: "Ajustes", .pt: "Ajustes"],
        "common.success": [.zhHans: "成功", .en: "Success", .ja: "成功", .ko: "성공", .ru: "Успех", .ar: "نجاح", .fr: "Succès", .de: "Erfolg", .es: "Éxito", .pt: "Sucesso"],
        "common.test_config": [.zhHans: "检测配置", .en: "Test config", .ja: "設定をテスト", .ko: "설정 테스트", .ru: "Проверить", .ar: "اختبار الإعداد", .fr: "Tester", .de: "Testen", .es: "Probar", .pt: "Testar"],
        "common.version": [.zhHans: "版本", .en: "Version", .ja: "バージョン", .ko: "버전", .ru: "Версия", .ar: "الإصدار", .fr: "Version", .de: "Version", .es: "Versión", .pt: "Versão"],
        "config.api_key": [.zhHans: "API 密钥", .en: "API key", .ja: "APIキー", .ko: "API 키", .ru: "API-ключ", .ar: "مفتاح API", .fr: "Clé API", .de: "API-Schlüssel", .es: "Clave API", .pt: "Chave API"],
        "config.chatgpt": [.zhHans: "ChatGPT 配置", .en: "ChatGPT config", .ja: "ChatGPT 設定", .ko: "ChatGPT 설정", .ru: "ChatGPT", .ar: "إعداد ChatGPT", .fr: "Config ChatGPT", .de: "ChatGPT-Konfig.", .es: "Config ChatGPT", .pt: "Config ChatGPT"],
        "config.chatgpt_sub": [.zhHans: "数据获取方式", .en: "Data source", .ja: "データ取得方法", .ko: "데이터 가져오기", .ru: "Источник данных", .ar: "مصدر البيانات", .fr: "Source des données", .de: "Datenquelle", .es: "Fuente de datos", .pt: "Fonte de dados"],
        "config.claude": [.zhHans: "Claude 配置", .en: "Claude config", .ja: "Claude 設定", .ko: "Claude 설정", .ru: "Claude", .ar: "إعداد Claude", .fr: "Config Claude", .de: "Claude-Konfig.", .es: "Config Claude", .pt: "Config Claude"],
        "config.configured": [.zhHans: "已配置", .en: "Configured", .ja: "設定済み", .ko: "구성됨", .ru: "Настроено", .ar: "مُعدّ", .fr: "Configuré", .de: "Konfiguriert", .es: "Configurado", .pt: "Configurado"],
        "config.copilot": [.zhHans: "Copilot 配置", .en: "Copilot config", .ja: "Copilot 設定", .ko: "Copilot 설정", .ru: "Copilot", .ar: "إعداد Copilot", .fr: "Config Copilot", .de: "Copilot-Konfig.", .es: "Config Copilot", .pt: "Config Copilot"],
        "config.credentials": [.zhHans: "凭证状态", .en: "Credentials", .ja: "認証状態", .ko: "자격 증명", .ru: "Учётные данные", .ar: "بيانات الاعتماد", .fr: "Identifiants", .de: "Anmeldedaten", .es: "Credenciales", .pt: "Credenciais"],
        "config.current": [.zhHans: "当前配置", .en: "Current config", .ja: "現在の設定", .ko: "현재 설정", .ru: "Текущая", .ar: "الإعداد الحالي", .fr: "Config actuelle", .de: "Aktuell", .es: "Config actual", .pt: "Config atual"],
        "config.fail_prefix": [.zhHans: "失败：", .en: "Failed: ", .ja: "失敗：", .ko: "실패: ", .ru: "Ошибка: ", .ar: "فشل: ", .fr: "Échec : ", .de: "Fehler: ", .es: "Error: ", .pt: "Falha: "],
        "config.grok": [.zhHans: "Grok 配置", .en: "Grok config", .ja: "Grok 設定", .ko: "Grok 설정", .ru: "Grok", .ar: "إعداد Grok", .fr: "Config Grok", .de: "Grok-Konfig.", .es: "Config Grok", .pt: "Config Grok"],
        "config.kimi": [.zhHans: "Kimi 配置", .en: "Kimi config", .ja: "Kimi 設定", .ko: "Kimi 설정", .ru: "Kimi", .ar: "إعداد Kimi", .fr: "Config Kimi", .de: "Kimi-Konfig.", .es: "Config Kimi", .pt: "Config Kimi"],
        "config.minimax": [.zhHans: "MiniMax 配置", .en: "MiniMax config", .ja: "MiniMax 設定", .ko: "MiniMax 설정", .ru: "MiniMax", .ar: "إعداد MiniMax", .fr: "Config MiniMax", .de: "MiniMax-Konfig.", .es: "Config MiniMax", .pt: "Config MiniMax"],
        "config.probe_available": [.zhHans: "成功：探针可用", .en: "Success: probe available", .ja: "成功：検出可能", .ko: "성공: 감지 가능", .ru: "Успех: проверка доступна", .ar: "نجاح: الكشف متاح", .fr: "Succès : sonde dispo", .de: "Erfolg: Sonde bereit", .es: "Éxito: sonda disponible", .pt: "Sucesso: sonda disponível"],
        "config.probe_mode": [.zhHans: "探测模式", .en: "Probe mode", .ja: "検出モード", .ko: "감지 모드", .ru: "Режим проверки", .ar: "وضع الكشف", .fr: "Mode de sonde", .de: "Prüfmodus", .es: "Modo de sonda", .pt: "Modo de sonda"],
        "config.probe_pending": [.zhHans: "待配置：本机尚未就绪", .en: "Pending: not ready on this Mac", .ja: "未準備：このMacでは未設定", .ko: "대기: 이 Mac에 준비 안 됨", .ru: "Ожидание: ещё не готово", .ar: "قيد الانتظار: غير جاهز", .fr: "En attente : pas prêt", .de: "Ausstehend: noch nicht bereit", .es: "Pendiente: no listo", .pt: "Pendente: não pronto"],
        "config.region": [.zhHans: "区域", .en: "Region", .ja: "リージョン", .ko: "지역", .ru: "Регион", .ar: "المنطقة", .fr: "Région", .de: "Region", .es: "Región", .pt: "Região"],
        "config.success_creds": [.zhHans: "成功：已找到凭证", .en: "Success: credentials found", .ja: "成功：認証情報あり", .ko: "성공: 자격 증명 있음", .ru: "Успех: учётные данные найдены", .ar: "نجاح: وُجدت بيانات الاعتماد", .fr: "Succès : identifiants trouvés", .de: "Erfolg: Anmeldedaten gefunden", .es: "Éxito: credenciales halladas", .pt: "Sucesso: credenciais encontradas"],
        "config.success_ok": [.zhHans: "成功：连接正常", .en: "Success: connected", .ja: "成功：接続OK", .ko: "성공: 연결됨", .ru: "Успех: подключено", .ar: "نجاح: متصل", .fr: "Succès : connecté", .de: "Erfolg: verbunden", .es: "Éxito: conectado", .pt: "Sucesso: conectado"],
        "menu.empty_body": [.zhHans: "请在设置中开启需要监控的会员", .en: "Enable memberships in Settings", .ja: "設定でメンバーシップを有効にしてください", .ko: "설정에서 멤버십을 켜 주세요", .ru: "Включите подписки в настройках", .ar: "فعّل العضويات من الإعدادات", .fr: "Activez des abonnements dans Réglages", .de: "Aktivieren Sie Abos in den Einstellungen", .es: "Activa membresías en Ajustes", .pt: "Ative assinaturas em Ajustes"],
        "menu.empty_title": [.zhHans: "未启用会员", .en: "No memberships enabled", .ja: "メンバー未有効", .ko: "멤버십 없음", .ru: "Нет активных подписок", .ar: "لا عضويات مفعّلة", .fr: "Aucun abonnement", .de: "Keine Abos aktiv", .es: "Sin membresías", .pt: "Sem assinaturas"],
        "menu.fetching": [.zhHans: "正在获取额度…", .en: "Fetching usage data…", .ja: "使用量を取得中…", .ko: "사용량 가져오는 중…", .ru: "Загрузка данных…", .ar: "جارٍ جلب البيانات…", .fr: "Récupération…", .de: "Lade Daten…", .es: "Obteniendo datos…", .pt: "Buscando dados…"],
        "menu.left_pct": [.zhHans: "% 剩余", .en: "% left", .ja: "% 残り", .ko: "% 남음", .ru: "% осталось", .ar: "% متبقٍ", .fr: "% restant", .de: "% übrig", .es: "% restante", .pt: "% restante"],
        "menu.no_usage": [.zhHans: "暂无用量数据", .en: "No usage data", .ja: "使用データなし", .ko: "사용 데이터 없음", .ru: "Нет данных использования", .ar: "لا بيانات استخدام", .fr: "Aucune donnée d’usage", .de: "Keine Nutzungsdaten", .es: "Sin datos de uso", .pt: "Sem dados de uso"],
        "menu.open_dashboard": [.zhHans: "打开后台", .en: "Dashboard", .ja: "ダッシュボード", .ko: "대시보드", .ru: "Кабинет", .ar: "لوحة التحكم", .fr: "Tableau de bord", .de: "Dashboard", .es: "Panel", .pt: "Painel"],
        "menu.pin": [.zhHans: "固定窗口", .en: "Pin window", .ja: "ウィンドウ固定", .ko: "창 고정", .ru: "Закрепить", .ar: "تثبيت النافذة", .fr: "Épingler", .de: "Anheften", .es: "Fijar", .pt: "Fixar"],
        "menu.refresh": [.zhHans: "刷新", .en: "Refresh", .ja: "更新", .ko: "새로고침", .ru: "Обновить", .ar: "تحديث", .fr: "Actualiser", .de: "Aktualisieren", .es: "Actualizar", .pt: "Atualizar"],
        "menu.sort_mode": [.zhHans: "排序模式 · 用右侧箭头调整顺序", .en: "Reorder mode · use arrows on the right", .ja: "並び替え · 右の矢印で調整", .ko: "정렬 모드 · 오른쪽 화살표로 조정", .ru: "Порядок · стрелки справа", .ar: "وضع الترتيب · استخدم الأسهم يمينًا", .fr: "Réordonner · flèches à droite", .de: "Sortieren · Pfeile rechts", .es: "Reordenar · flechas a la derecha", .pt: "Reordenar · setas à direita"],
        "menu.unavailable": [.zhHans: "不可用", .en: "Unavailable", .ja: "利用不可", .ko: "사용 불가", .ru: "Недоступно", .ar: "غير متاح", .fr: "Indisponible", .de: "Nicht verfügbar", .es: "No disponible", .pt: "Indisponível"],
        "menu.unpin": [.zhHans: "取消固定", .en: "Unpin", .ja: "固定解除", .ko: "고정 해제", .ru: "Открепить", .ar: "إلغاء التثبيت", .fr: "Désépingler", .de: "Lösen", .es: "Desfijar", .pt: "Desafixar"],
        "menu.updated": [.zhHans: "已更新", .en: "Updated", .ja: "更新済み", .ko: "업데이트됨", .ru: "Обновлено", .ar: "تم التحديث", .fr: "Mis à jour", .de: "Aktualisiert", .es: "Actualizado", .pt: "Atualizado"],
        // Card primary meters: 5H · 7D · 总额
        "quota.5h": [.zhHans: "5H", .en: "5H", .ja: "5H", .ko: "5H", .ru: "5H", .ar: "5H", .fr: "5H", .de: "5H", .es: "5H", .pt: "5H"],
        "quota.monthly": [.zhHans: "总额", .en: "总额", .ja: "总额", .ko: "总额", .ru: "总额", .ar: "总额", .fr: "总额", .de: "总额", .es: "总额", .pt: "总额"],
        "quota.next_renewal": [.zhHans: "下次续费", .en: "Next renewal", .ja: "次回更新", .ko: "다음 갱신", .ru: "След. продление", .ar: "التجديد التالي", .fr: "Prochain renouvellement", .de: "Nächste Verlängerung", .es: "Próxima renovación", .pt: "Próxima renovação"],
        "quota.pick_activation": [.zhHans: "点日期选开通日，按自然月自动算下次续费", .en: "Pick activation date; next renewal is calendar-month based", .ja: "開始日を選ぶと自然月で次回更新を計算", .ko: "개통일을 선택하면 자연월 기준으로 다음 갱신 계산", .ru: "Выберите дату активации; продление по календарному месяцу", .ar: "اختر تاريخ التفعيل؛ التجديد حسب الشهر الميلادي", .fr: "Choisissez la date d’activation ; renouvellement au mois civil", .de: "Aktivierungsdatum wählen; Verlängerung monatsbasiert", .es: "Elige fecha de activación; renovación por mes natural", .pt: "Escolha a data de ativação; renovação por mês civil"],
        "quota.plan_unset": [.zhHans: "套餐未设置", .en: "Plan not set", .ja: "プラン未設定", .ko: "요금제 미설정", .ru: "План не задан", .ar: "الخطة غير محددة", .fr: "Offre non définie", .de: "Tarif nicht gesetzt", .es: "Plan no definido", .pt: "Plano não definido"],
        "quota.renewal": [.zhHans: "续费", .en: "Renews", .ja: "更新", .ko: "갱신", .ru: "Продление", .ar: "التجديد", .fr: "Renouvellement", .de: "Verlängerung", .es: "Renovación", .pt: "Renovação"],
        "quota.session": [.zhHans: "会话", .en: "Session", .ja: "セッション", .ko: "세션", .ru: "Сессия", .ar: "جلسة", .fr: "Session", .de: "Sitzung", .es: "Sesión", .pt: "Sessão"],
        "quota.weekly": [.zhHans: "7D", .en: "7D", .ja: "7D", .ko: "7D", .ru: "7D", .ar: "7D", .fr: "7D", .de: "7D", .es: "7D", .pt: "7D"],
        "settings.about": [.zhHans: "关于", .en: "About", .ja: "について", .ko: "정보", .ru: "О программе", .ar: "حول", .fr: "À propos", .de: "Info", .es: "Acerca de", .pt: "Sobre"],
        "settings.about_version_fmt": [.zhHans: "版本 %@（构建 %@）", .en: "Version %@ (Build %@)", .ja: "バージョン %@（ビルド %@）", .ko: "버전 %@（빌드 %@）", .ru: "Версия %@ (сборка %@)", .ar: "الإصدار %@ (البناء %@)", .fr: "Version %@ (build %@)", .de: "Version %@ (Build %@)", .es: "Versión %@ (compilación %@)", .pt: "Versão %@ (build %@)"],
        "settings.about_version_help": [.zhHans: "版本号为功能版本；构建号表示同版本内的打包序号（每次发版递增）。", .en: "Version is the feature release; build is the package number within that version.", .ja: "バージョンは機能版、ビルドは同一版内の通番です。", .ko: "버전은 기능 버전, 빌드는 같은 버전 내 패키지 번호입니다.", .ru: "Версия — функциональный релиз; сборка — номер пакета.", .ar: "الإصدار للنسخة الوظيفية؛ البناء رقم الحزمة داخل الإصدار.", .fr: "Version = fonctionnalité ; build = n° de paquet.", .de: "Version = Feature-Release; Build = Paketnummer.", .es: "Versión = funcional; build = número de empaquetado.", .pt: "Versão = recurso; build = número do pacote."],
        "settings.appearance": [.zhHans: "外观", .en: "Appearance", .ja: "外観", .ko: "모양", .ru: "Оформление", .ar: "المظهر", .fr: "Apparence", .de: "Darstellung", .es: "Apariencia", .pt: "Aparência"],
        "settings.bg_sync": [.zhHans: "后台同步", .en: "Background sync", .ja: "バックグラウンド同期", .ko: "백그라운드 동기화", .ru: "Фоновая синхронизация", .ar: "مزامنة الخلفية", .fr: "Sync en arrière-plan", .de: "Hintergrund-Sync", .es: "Sincronización en segundo plano", .pt: "Sincronização em segundo plano"],
        "settings.bg_sync_help": [.zhHans: "后台刷新菜单栏。选「关闭」最省电（仅打开菜单时更新）。建议 15 分钟；过快会增加 CPU 与耗电。", .en: "Background menu-bar refresh. Off is best for battery (refresh when menu opens). Prefer 15 min; faster uses more CPU.", .ja: "メニューバーのバックグラウンド更新。オフが省電力。15分推奨。", .ko: "메뉴바 백그라운드 새로고침. 끄면 절전. 15분 권장.", .ru: "Фоновое обновление. Выкл. — экономия. Лучше 15 мин.", .ar: "تحديث خلفي. الإيقاف أوفر. يُفضّل 15 دقيقة.", .fr: "Actualisation en arrière-plan. Off = batterie. Préférez 15 min.", .de: "Hintergrundaktualisierung. Aus = sparsam. Besser 15 Min.", .es: "Actualización en segundo plano. Off ahorra. Mejor 15 min.", .pt: "Atualização em segundo plano. Off economiza. Prefira 15 min."],
        "settings.bg_sync_sub": [.zhHans: "自动保持数据最新", .en: "Keep data fresh automatically", .ja: "データを自動更新", .ko: "데이터를 자동으로 최신 유지", .ru: "Автообновление данных", .ar: "إبقاء البيانات محدّثة تلقائيًا", .fr: "Garder les données à jour", .de: "Daten automatisch frisch halten", .es: "Mantener datos actualizados", .pt: "Manter dados atualizados"],
        "settings.choose_theme": [.zhHans: "选择主题", .en: "Choose theme", .ja: "テーマを選択", .ko: "테마 선택", .ru: "Выберите тему", .ar: "اختر السمة", .fr: "Choisir le thème", .de: "Theme wählen", .es: "Elegir tema", .pt: "Escolher tema"],
        "settings.display_remaining": [.zhHans: "剩余", .en: "Remaining", .ja: "残り", .ko: "남음", .ru: "Остаток", .ar: "متبقٍ", .fr: "Restant", .de: "Verbleibend", .es: "Restante", .pt: "Restante"],
        "settings.display_used": [.zhHans: "已用", .en: "Used", .ja: "使用済み", .ko: "사용", .ru: "Использова.", .ar: "مستخدم", .fr: "Utilisé", .de: "Verbraucht", .es: "Usado", .pt: "Usado"],
        "settings.language": [.zhHans: "语言", .en: "Language", .ja: "言語", .ko: "언어", .ru: "Язык", .ar: "اللغة", .fr: "Langue", .de: "Sprache", .es: "Idioma", .pt: "Idioma"],
        "settings.language_hint": [.zhHans: "立即生效，无需重启", .en: "Applies immediately, no restart needed", .ja: "すぐに反映、再起動不要", .ko: "즉시 적용, 재시작 불필요", .ru: "Применяется сразу, без перезапуска", .ar: "يُطبَّق فورًا دون إعادة تشغيل", .fr: "Prend effet immédiatement", .de: "Sofort wirksam, kein Neustart", .es: "Se aplica al instante", .pt: "Aplica-se imediatamente"],
        "settings.language_sub": [.zhHans: "切换界面显示语言", .en: "Switch interface language", .ja: "表示言語を切り替え", .ko: "인터페이스 언어 전환", .ru: "Язык интерфейса", .ar: "تبديل لغة الواجهة", .fr: "Changer la langue de l’interface", .de: "Oberflächensprache wechseln", .es: "Cambiar idioma de la interfaz", .pt: "Alterar idioma da interface"],
        "settings.launch": [.zhHans: "登录时启动", .en: "Launch at login", .ja: "ログイン時に起動", .ko: "로그인 시 시작", .ru: "Запуск при входе", .ar: "التشغيل عند تسجيل الدخول", .fr: "Lancer à la connexion", .de: "Beim Anmelden starten", .es: "Abrir al iniciar sesión", .pt: "Abrir ao iniciar sessão"],
        "settings.launch_sub": [.zhHans: "开机登录后自动启动本软件", .en: "Start automatically after login", .ja: "ログイン後に自動起動", .ko: "로그인 후 자동 시작", .ru: "Автозапуск после входа", .ar: "تشغيل تلقائي بعد تسجيل الدخول", .fr: "Démarrage automatique", .de: "Automatisch nach Anmeldung", .es: "Inicio automático", .pt: "Início automático"],
        "settings.logs": [.zhHans: "日志", .en: "Logs", .ja: "ログ", .ko: "로그", .ru: "Журналы", .ar: "السجلات", .fr: "Journaux", .de: "Protokolle", .es: "Registros", .pt: "Logs"],
        "settings.logs_sub": [.zhHans: "查看应用日志", .en: "View app logs", .ja: "アプリログを表示", .ko: "앱 로그 보기", .ru: "Просмотр логов", .ar: "عرض سجلات التطبيق", .fr: "Voir les journaux", .de: "App-Protokolle anzeigen", .es: "Ver registros", .pt: "Ver logs"],
        "settings.members": [.zhHans: "会员开关", .en: "Memberships", .ja: "メンバーシップ", .ko: "멤버십", .ru: "Подписки", .ar: "العضويات", .fr: "Abonnements", .de: "Abos", .es: "Membresías", .pt: "Assinaturas"],
        "settings.members_count": [.zhHans: "共 %@ 个 · 已开 %@ 个", .en: "%@ total · %@ on", .ja: "全 %@ · 有効 %@", .ko: "전체 %@ · 켜짐 %@", .ru: "Всего %@ · вкл. %@", .ar: "الإجمالي %@ · مفعّل %@", .fr: "%@ au total · %@ activés", .de: "%@ gesamt · %@ an", .es: "%@ en total · %@ activos", .pt: "%@ no total · %@ ativos"],
        "settings.members_hint": [.zhHans: "开启后，该会员会出现在下方「额度检测配置」中，可查看如何检测并测试连接。", .en: "Enabled memberships appear under Quota Detection for setup and testing.", .ja: "有効にすると「枠検出設定」に表示され、検出方法の確認とテストができます。", .ko: "켜면 아래「한도 감지 설정」에 나타나 감지 방법 확인과 테스트가 가능합니다.", .ru: "Включённые подписки появятся в «Проверка квот» для настройки.", .ar: "العضويات المفعّلة تظهر في «إعدادات الكشف» للإعداد والاختبار.", .fr: "Les abonnements activés apparaissent sous Détection des quotas.", .de: "Aktive Abos erscheinen unter Kontingenterkennung.", .es: "Las membresías activas aparecen en Detección de cuotas.", .pt: "Assinaturas ativas aparecem em Detecção de cotas."],
        "settings.probe": [.zhHans: "额度检测配置", .en: "Quota detection", .ja: "枠検出設定", .ko: "한도 감지 설정", .ru: "Проверка квот", .ar: "إعدادات كشف الحصة", .fr: "Détection des quotas", .de: "Kontingenterkennung", .es: "Detección de cuotas", .pt: "Detecção de cotas"],
        "settings.probe_empty": [.zhHans: "请先在「会员开关」启用会员", .en: "Enable memberships above first", .ja: "先にメンバーシップを有効にしてください", .ko: "먼저 위에서 멤버십을 켜 주세요", .ru: "Сначала включите подписки выше", .ar: "فعّل العضويات أعلاه أولًا", .fr: "Activez d’abord des abonnements", .de: "Zuerst Abos oben aktivieren", .es: "Activa membresías arriba primero", .pt: "Ative assinaturas acima primeiro"],
        "settings.probe_empty_body": [.zhHans: "打开上方「会员开关」后，对应会员会出现在这里，可查看并检测额度来源。", .en: "Turn on memberships above to configure how each quota is detected.", .ja: "上で有効にすると、ここに検出方法が表示されます。", .ko: "위에서 켜면 여기에 감지 방법이 표시됩니다.", .ru: "Включите подписки выше, чтобы настроить проверку.", .ar: "فعّل العضويات أعلاه لضبط طريقة الكشف.", .fr: "Activez des abonnements pour configurer la détection.", .de: "Aktivieren Sie Abos oben, um die Erkennung zu konfigurieren.", .es: "Activa membresías para configurar la detección.", .pt: "Ative assinaturas para configurar a detecção."],
        "settings.probe_sub": [.zhHans: "已启用 %@ 个会员 · 展开配置检测方式", .en: "%@ enabled · expand to configure detection", .ja: "%@ 件有効 · 展開して検出を設定", .ko: "%@개 켜짐 · 펼쳐 감지 설정", .ru: "%@ вкл. · разверните для настройки", .ar: "%@ مفعّل · وسّع لضبط الكشف", .fr: "%@ activés · développer pour configurer", .de: "%@ aktiv · aufklappen zum Konfigurieren", .es: "%@ activos · expandir para configurar", .pt: "%@ ativos · expandir para configurar"],
        "settings.quota_display": [.zhHans: "额度显示", .en: "Quota display", .ja: "枠の表示", .ko: "한도 표시", .ru: "Отображение квоты", .ar: "عرض الحصة", .fr: "Affichage du quota", .de: "Kontingentanzeige", .es: "Visualización de cuota", .pt: "Exibição de cota"],
        "settings.quota_display_sub": [.zhHans: "百分比按剩余或已用展示", .en: "Show percent as remaining or used", .ja: "残り／使用済みで表示", .ko: "남은량 또는 사용량으로 표시", .ru: "Процент: остаток или израсходовано", .ar: "النسبة كمتبقٍ أو مستخدم", .fr: "Pourcentage restant ou utilisé", .de: "Prozent als Rest oder verbraucht", .es: "Porcentaje restante o usado", .pt: "Percentual restante ou usado"],
        "settings.menu_bar_status_icon": [
            .zhHans: "状态栏额度图标",
            .en: "Menu bar status icon",
            .ja: "メニューバー状態アイコン",
            .ko: "메뉴 막대 상태 아이콘",
            .ru: "Иконка статуса в меню",
            .ar: "أيقونة الحالة في الشريط",
            .fr: "Icône d’état barre de menu",
            .de: "Menüleisten-Statussymbol",
            .es: "Icono de estado en barra",
            .pt: "Ícone de status na barra",
        ],
        "settings.menu_bar_status_icon_sub": [
            .zhHans: "关闭时显示 Logo；开启后按额度显示绿柱/感叹三角等",
            .en: "Off: brand logo. On: bars / warning triangle by quota status",
            .ja: "オフ：ロゴ／オン：残量に応じた棒・警告三角",
            .ko: "끔: 로고 / 켬: 한도에 따른 막대·경고 삼각",
            .ru: "Выкл.: логотип. Вкл.: столбцы / треугольник по квоте",
            .ar: "إيقاف: الشعار. تشغيل: أشرطة/مثلث حسب الحصة",
            .fr: "Off : logo. On : barres / triangle selon le quota",
            .de: "Aus: Logo. An: Balken / Warndreieck nach Kontingent",
            .es: "Off: logo. On: barras / triángulo según cuota",
            .pt: "Off: logo. On: barras / triângulo conforme cota",
        ],
        "settings.refresh_interval": [.zhHans: "刷新间隔", .en: "Refresh interval", .ja: "更新間隔", .ko: "새로고침 간격", .ru: "Интервал обновления", .ar: "فاصل التحديث", .fr: "Intervalle d’actualisation", .de: "Aktualisierungsintervall", .es: "Intervalo de actualización", .pt: "Intervalo de atualização"],
        "settings.theme.dark": [.zhHans: "深色", .en: "Dark", .ja: "ダーク", .ko: "다크", .ru: "Тёмная", .ar: "داكن", .fr: "Sombre", .de: "Dunkel", .es: "Oscuro", .pt: "Escuro"],
        "settings.theme.light": [.zhHans: "浅色", .en: "Light", .ja: "ライト", .ko: "라이트", .ru: "Светлая", .ar: "فاتح", .fr: "Clair", .de: "Hell", .es: "Claro", .pt: "Claro"],
        "settings.theme.system": [.zhHans: "跟随系统", .en: "System", .ja: "システム", .ko: "시스템", .ru: "Системная", .ar: "النظام", .fr: "Système", .de: "System", .es: "Sistema", .pt: "Sistema"],
        "settings.title": [.zhHans: "设置", .en: "Settings", .ja: "設定", .ko: "설정", .ru: "Настройки", .ar: "الإعدادات", .fr: "Réglages", .de: "Einstellungen", .es: "Ajustes", .pt: "Ajustes"],
        "settings.updates": [.zhHans: "软件更新", .en: "Updates", .ja: "アップデート", .ko: "업데이트", .ru: "Обновления", .ar: "التحديثات", .fr: "Mises à jour", .de: "Updates", .es: "Actualizaciones", .pt: "Atualizações"],
        "settings.updates_version_fmt": [.zhHans: "当前版本 %@", .en: "Current version %@", .ja: "現在のバージョン %@", .ko: "현재 버전 %@", .ru: "Текущая версия %@", .ar: "الإصدار الحالي %@", .fr: "Version actuelle %@", .de: "Aktuelle Version %@", .es: "Versión actual %@", .pt: "Versão atual %@"],
        "settings.updates_manual_help": [
            .zhHans: "仅手动检查。从 GitHub 公开 Release 读取版本；不自动下载、不静默安装。",
            .en: "Manual check only. Reads public GitHub Releases; no auto-download or silent install.",
            .ja: "手動チェックのみ。GitHub の公開 Release を参照し、自動ダウンロードしません。",
            .ko: "수동 확인만. GitHub 공개 Release를 조회하며 자동 다운로드하지 않습니다.",
            .ru: "Только вручную. Публичные GitHub Releases; без автозагрузки.",
            .ar: "فحص يدوي فقط. يقرأ إصدارات GitHub العامة؛ بلا تنزيل تلقائي.",
            .fr: "Vérification manuelle. Releases GitHub publics ; pas de téléchargement auto.",
            .de: "Nur manuell. Öffentliche GitHub Releases; kein Auto-Download.",
            .es: "Solo manual. Lee Releases públicos de GitHub; sin descarga automática.",
            .pt: "Apenas manual. Lê Releases públicos do GitHub; sem download automático.",
        ],
        "settings.updates_check": [.zhHans: "检查更新", .en: "Check for updates", .ja: "更新を確認", .ko: "업데이트 확인", .ru: "Проверить обновления", .ar: "التحقق من التحديثات", .fr: "Vérifier les mises à jour", .de: "Nach Updates suchen", .es: "Buscar actualizaciones", .pt: "Verificar atualizações"],
        "settings.updates_checking": [.zhHans: "检查中…", .en: "Checking…", .ja: "確認中…", .ko: "확인 중…", .ru: "Проверка…", .ar: "جارٍ الفحص…", .fr: "Vérification…", .de: "Prüfen…", .es: "Comprobando…", .pt: "Verificando…"],
        "settings.updates_up_to_date": [.zhHans: "已是最新（%@）", .en: "You’re up to date (%@)", .ja: "最新です（%@）", .ko: "최신입니다 (%@)", .ru: "Уже последняя (%@)", .ar: "أنت على أحدث إصدار (%@)", .fr: "À jour (%@)", .de: "Aktuell (%@)", .es: "Está al día (%@)", .pt: "Está atualizado (%@)"],
        "settings.updates_available_fmt": [.zhHans: "发现新版本 %@（当前 %@）", .en: "Update available: %@ (you have %@)", .ja: "新バージョン %@（現在 %@）", .ko: "새 버전 %@ (현재 %@)", .ru: "Доступна %@ (у вас %@)", .ar: "يتوفر %@ (لديك %@)", .fr: "Nouvelle version %@ (vous avez %@)", .de: "Update %@ verfügbar (Sie haben %@)", .es: "Nueva versión %@ (tienes %@)", .pt: "Nova versão %@ (você tem %@)"],
        "settings.updates_download": [.zhHans: "去下载", .en: "Download", .ja: "ダウンロード", .ko: "다운로드", .ru: "Скачать", .ar: "تنزيل", .fr: "Télécharger", .de: "Herunterladen", .es: "Descargar", .pt: "Baixar"],
        "settings.updates_install": [.zhHans: "下载安装", .en: "Download & open", .ja: "DLして開く", .ko: "다운로드 후 열기", .ru: "Скачать и открыть", .ar: "تنزيل وفتح", .fr: "Télécharger", .de: "Laden & öffnen", .es: "Descargar y abrir", .pt: "Baixar e abrir"],
        "settings.updates_downloading": [.zhHans: "正在下载安装包…", .en: "Downloading installer…", .ja: "ダウンロード中…", .ko: "다운로드 중…", .ru: "Загрузка…", .ar: "جارٍ التنزيل…", .fr: "Téléchargement…", .de: "Wird geladen…", .es: "Descargando…", .pt: "Baixando…"],
        "settings.updates_downloading_btn": [.zhHans: "下载中…", .en: "Downloading…", .ja: "DL中…", .ko: "다운로드 중…", .ru: "Загрузка…", .ar: "جارٍ التنزيل…", .fr: "Téléchargement…", .de: "Laden…", .es: "Descargando…", .pt: "Baixando…"],
        "settings.updates_progress_fmt": [.zhHans: "已下载 %d%%", .en: "Downloaded %d%%", .ja: "%d%% 完了", .ko: "%d%% 완료", .ru: "Скачано %d%%", .ar: "تم تنزيل %d٪", .fr: "%d %% téléchargé", .de: "%d %% geladen", .es: "Descargado %d%%", .pt: "Baixado %d%%"],
        "settings.updates_opening": [.zhHans: "正在打开安装包…", .en: "Opening installer…", .ja: "インストーラを開いています…", .ko: "설치 파일 여는 중…", .ru: "Открытие…", .ar: "جارٍ الفتح…", .fr: "Ouverture…", .de: "Wird geöffnet…", .es: "Abriendo…", .pt: "Abrindo…"],
        "settings.updates_opened": [.zhHans: "已打开，请拖到应用程序", .en: "Opened — drag into Applications", .ja: "開きました。Applications へドラッグ", .ko: "열림 · 응용 프로그램으로 드래그", .ru: "Открыто — перетащите в Applications", .ar: "فُتح — اسحب إلى التطبيقات", .fr: "Ouvert — glissez vers Applications", .de: "Geöffnet — in Programme ziehen", .es: "Abierto — arrastra a Aplicaciones", .pt: "Aberto — arraste para Aplicativos"],
        "settings.updates_opened_fmt": [.zhHans: "已打开 %@ · 拖到应用程序", .en: "Opened %@ · drag to Applications", .ja: "%@ を開きました", .ko: "%@ 열림 · 응용 프로그램으로", .ru: "Открыто %@", .ar: "فُتح %@", .fr: "%@ ouvert", .de: "%@ geöffnet", .es: "Abierto %@", .pt: "Aberto %@"],
        "settings.updates_quitting": [
            .zhHans: "安装包已打开，即将退出以便替换…",
            .en: "Installer opened — quitting so you can replace…",
            .ja: "インストーラを開きました。終了して置き換えます…",
            .ko: "설치 파일을 열었습니다. 교체를 위해 종료합니다…",
            .ru: "Установщик открыт — выход для замены…",
            .ar: "فُتح المثبّت — جارٍ الخروج للاستبدال…",
            .fr: "Installateur ouvert — fermeture pour remplacer…",
            .de: "Installer geöffnet — Beenden zum Ersetzen…",
            .es: "Instalador abierto — saliendo para reemplazar…",
            .pt: "Instalador aberto — saindo para substituir…",
        ],
        "settings.updates_open_page": [.zhHans: "已打开下载页", .en: "Opened release page", .ja: "リリースページを開きました", .ko: "릴리스 페이지를 열었습니다", .ru: "Страница релиза открыта", .ar: "فُتحت صفحة الإصدار", .fr: "Page de release ouverte", .de: "Release-Seite geöffnet", .es: "Página de release abierta", .pt: "Página de release aberta"],
        "settings.updates_failed_fmt": [.zhHans: "检查失败：%@", .en: "Check failed: %@", .ja: "確認失敗：%@", .ko: "확인 실패: %@", .ru: "Ошибка: %@", .ar: "فشل الفحص: %@", .fr: "Échec : %@", .de: "Fehler: %@", .es: "Error: %@", .pt: "Falha: %@"],
        "settings.updates_failed_version": [.zhHans: "无法识别当前版本号", .en: "Could not read the current version", .ja: "現在のバージョンを読めません", .ko: "현재 버전을 읽을 수 없습니다", .ru: "Не удалось прочитать версию", .ar: "تعذّر قراءة الإصدار الحالي", .fr: "Version actuelle illisible", .de: "Aktuelle Version unlesbar", .es: "No se pudo leer la versión", .pt: "Não foi possível ler a versão"],
        "settings.updates_failed_none": [.zhHans: "未找到可用的 Mac 发布包", .en: "No Mac release found", .ja: "Mac 用リリースが見つかりません", .ko: "Mac 릴리스를 찾지 못했습니다", .ru: "Mac-релиз не найден", .ar: "لم يُعثر على إصدار Mac", .fr: "Aucune release Mac trouvée", .de: "Kein Mac-Release gefunden", .es: "No hay release de Mac", .pt: "Nenhum release Mac encontrado"],
        "status.critical": [.zhHans: "紧张", .en: "Low", .ja: "低下", .ko: "부족", .ru: "Мало", .ar: "منخفض", .fr: "Bas", .de: "Niedrig", .es: "Bajo", .pt: "Baixo"],
        "status.depleted": [.zhHans: "用尽", .en: "Empty", .ja: "枯渇", .ko: "소진", .ru: "Исчерпано", .ar: "نافد", .fr: "Épuisé", .de: "Leer", .es: "Agotado", .pt: "Esgotado"],
        "status.error": [.zhHans: "错误", .en: "Error", .ja: "エラー", .ko: "오류", .ru: "Ошибка", .ar: "خطأ", .fr: "Erreur", .de: "Fehler", .es: "Error", .pt: "Erro"],
        "status.healthy": [.zhHans: "充足", .en: "Healthy", .ja: "良好", .ko: "양호", .ru: "Норма", .ar: "سليم", .fr: "OK", .de: "Gut", .es: "Bien", .pt: "OK"],
        "status.syncing": [.zhHans: "同步中", .en: "Syncing", .ja: "同期中", .ko: "동기화 중", .ru: "Синхр.", .ar: "مزامنة", .fr: "Sync", .de: "Sync", .es: "Sincronizando", .pt: "Sincronizando"],
        "status.warning": [.zhHans: "偏低", .en: "Warning", .ja: "注意", .ko: "주의", .ru: "Внимание", .ar: "تحذير", .fr: "Attention", .de: "Warnung", .es: "Aviso", .pt: "Aviso"],
        "probe.codex.title": [.zhHans: "ChatGPT 额度检测", .en: "ChatGPT detection", .ja: "ChatGPT 枠検出", .ko: "ChatGPT 한도 감지", .ru: "Проверка ChatGPT", .ar: "كشف ChatGPT", .fr: "Détection ChatGPT", .de: "ChatGPT-Erkennung", .es: "Detección ChatGPT", .pt: "Detecção ChatGPT"],
        "probe.codex.summary": [.zhHans: "通过 Codex CLI（RPC）或 ChatGPT OAuth（API）读取限速额度", .en: "Codex CLI (RPC) or ChatGPT OAuth (API) rate limits", .ja: "Codex CLI または OAuth API で枠を取得", .ko: "Codex CLI 또는 OAuth API로 한도 조회", .ru: "CLI Codex или OAuth API ChatGPT", .ar: "CLI Codex أو OAuth لـ ChatGPT", .fr: "CLI Codex ou OAuth ChatGPT", .de: "Codex-CLI oder ChatGPT-OAuth", .es: "CLI Codex u OAuth ChatGPT", .pt: "CLI Codex ou OAuth ChatGPT"],
        "probe.kimi.title": [.zhHans: "Kimi 额度检测", .en: "Kimi detection", .ja: "Kimi 枠検出", .ko: "Kimi 한도 감지", .ru: "Проверка Kimi", .ar: "كشف Kimi", .fr: "Détection Kimi", .de: "Kimi-Erkennung", .es: "Detección Kimi", .pt: "Detecção Kimi"],
        "probe.kimi.summary": [.zhHans: "CLI /usage 或 Coding API / Cookie 拉取额度", .en: "CLI /usage or Coding API / cookie", .ja: "CLI /usage または API / Cookie", .ko: "CLI /usage 또는 API / 쿠키", .ru: "CLI /usage или API / cookie", .ar: "CLI أو API / كوكي", .fr: "CLI /usage ou API / cookie", .de: "CLI /usage oder API / Cookie", .es: "CLI /usage o API / cookie", .pt: "CLI /usage ou API / cookie"],
        "probe.minimax.title": [.zhHans: "MiniMax 额度检测", .en: "MiniMax detection", .ja: "MiniMax 枠検出", .ko: "MiniMax 한도 감지", .ru: "Проверка MiniMax", .ar: "كشف MiniMax", .fr: "Détection MiniMax", .de: "MiniMax-Erkennung", .es: "Detección MiniMax", .pt: "Detecção MiniMax"],
        "probe.minimax.summary": [.zhHans: "Coding Plan API（国内/国际）Bearer Token", .en: "Coding Plan API (CN/Intl) with Bearer token", .ja: "Coding Plan API（国内/国際）", .ko: "Coding Plan API (국내/국제)", .ru: "API Coding Plan (CN/Intl)", .ar: "API Coding Plan", .fr: "API Coding Plan", .de: "Coding-Plan-API", .es: "API Coding Plan", .pt: "API Coding Plan"],
        "probe.grok.title": [.zhHans: "Grok 额度检测", .en: "Grok detection", .ja: "Grok 枠検出", .ko: "Grok 한도 감지", .ru: "Проверка Grok", .ar: "كشف Grok", .fr: "Détection Grok", .de: "Grok-Erkennung", .es: "Detección Grok", .pt: "Detecção Grok"],
        "probe.grok.summary": [.zhHans: "xAI OAuth + billing credits 接口", .en: "xAI OAuth + billing credits API", .ja: "xAI OAuth + 課金 API", .ko: "xAI OAuth + 결제 API", .ru: "xAI OAuth + billing API", .ar: "xAI OAuth + billing", .fr: "OAuth xAI + API facturation", .de: "xAI-OAuth + Billing-API", .es: "OAuth xAI + API de facturacion", .pt: "OAuth xAI + API de cobranca"],
        "probe.codex.step.0": [.zhHans: "RPC 模式：本机 codex app-server 拉取 5 小时 / 周限额", .en: "RPC mode: local codex app-server fetch 5 h / weekly limits"],
        "probe.codex.step.1": [.zhHans: "API 模式：读取 ~/.codex/auth.json，请求 ChatGPT 额度接口", .en: "API mode: read ~/.codex/auth.json，request ChatGPT 额度 API"],
        "probe.codex.step.2": [.zhHans: "推荐 API：稳定且无需常驻交互 CLI", .en: "prefer API：stable, no interactive CLI required"],
        "probe.kimi.step.0": [.zhHans: "CLI 模式：启动 kimi 交互命令并发送 /usage", .en: "CLI mode: start kimi interactive CLI and send /usage"],
        "probe.kimi.step.1": [.zhHans: "API 模式：优先 sk-kimi Coding Key，其次浏览器 Cookie", .en: "API mode: prefer sk-kimi Coding Key, else browser cookie"],
        "probe.kimi.step.2": [.zhHans: "查找顺序：环境变量 → kimi-desktop 本地 Key → 浏览器 kimi-auth", .en: "查找顺序：env var → kimi-desktop 本地 Key → 浏览器 kimi-auth"],
        "probe.minimax.step.0": [.zhHans: "按区域选择 minimaxi.com 或 minimax.io 接口", .en: "pick region  minimaxi.com  or minimax.io  API"],
        "probe.minimax.step.1": [.zhHans: "密钥顺序：环境变量 → 设置中保存的 Key → ~/.minimax/config.yaml", .en: "Key order: env var → saved API key → ~/.minimax/config.yaml"],
        "probe.minimax.step.2": [.zhHans: "成功后显示 Coding Plan 剩余额度", .en: "then show Coding Plan remaining"],
        "probe.grok.step.0": [.zhHans: "读取 ~/.grok/auth.json 中的 OAuth access token", .en: "read ~/.grok/auth.json 中的 OAuth access token"],
        "probe.grok.step.1": [.zhHans: "过期则用 refresh_token 向 auth.x.ai 刷新", .en: "refresh via refresh_token at auth.x.ai when expired"],
        "probe.grok.step.2": [.zhHans: "请求 cli-chat-proxy 的 billing?format=credits 得到额度", .en: "request cli-chat-proxy 的 billing?format=credits 得到额度"],
        "probe.claude.step.0": [.zhHans: "CLI 模式：运行 claude /usage 解析会话与周额度", .en: "CLI mode: run claude /usage for session/weekly quotas"],
        "probe.claude.step.1": [.zhHans: "API 模式：OAuth 凭证直连接口（可缓存约 15 分钟）", .en: "API mode: OAuth 凭证直连 API（可缓存约 15 分钟）"],
        "probe.claude.step.2": [.zhHans: "可选：Guest Pass 与 API 预算阈值", .en: "optional: Guest Pass and API budget"],
        "probe.gemini.step.0": [.zhHans: "读取 ~/.gemini/oauth_creds.json", .en: "read ~/.gemini/oauth_creds.json"],
        "probe.gemini.step.1": [.zhHans: "用 access token 请求 Gemini 用量 / 配额接口", .en: "用 access token request Gemini 用量 / 配额 API"],
        "probe.gemini.step.2": [.zhHans: "Token 过期时可尝试 CLI 刷新后再探测", .en: "on token expiry try CLI refresh then retry"],
        "probe.copilot.step.0": [.zhHans: "Billing 模式：GitHub Billing API（细粒度 PAT，Plan:read）", .en: "Billing mode: GitHub Billing API（细粒度 PAT，Plan:read）"],
        "probe.copilot.step.1": [.zhHans: "Internal 模式：api.github.com/copilot_internal/user（Classic PAT copilot）", .en: "Internal mode: api.github.com/copilot_internal/user（Classic PAT copilot）"],
        "probe.copilot.step.2": [.zhHans: "可配置用户名、月额度上限与手动覆盖", .en: "optional username, monthly limit, manual override"],
        "probe.cursor.step.0": [.zhHans: "读取 ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb", .en: "read ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"],
        "probe.cursor.step.1": [.zhHans: "从库中取出 access token，解码 JWT 得到 userId", .en: "read access token, decode JWT userId"],
        "probe.cursor.step.2": [.zhHans: "请求 https://cursor.com/api/usage-summary 解析 plan / on-demand", .en: "request https://cursor.com/api/usage-summary parse plan / on-demand"],
        "probe.antigravity.step.0": [.zhHans: "检测本机是否运行 Antigravity / 相关 CLI", .en: "detect local Antigravity / CLI"],
        "probe.antigravity.step.1": [.zhHans: "请求本地 HTTPS 接口（可含自签证书）", .en: "请求本地 HTTPS  API（可含自签证书）"],
        "probe.antigravity.step.2": [.zhHans: "解析返回的配额窗口与剩余比例", .en: "parse quota windows and remaining"],
        "probe.zai.step.0": [.zhHans: "优先从配置的 settings.json 路径读取 token", .en: "prefer 配置的 settings.json 路径read token"],
        "probe.zai.step.1": [.zhHans: "找不到则读环境变量（如 GLM_AUTH_TOKEN）", .en: "else 读env var（如 GLM_AUTH_TOKEN）"],
        "probe.zai.step.2": [.zhHans: "调用 Z.ai / GLM 用量接口", .en: "call Z.ai / GLM 用量 API"],
        "probe.bedrock.step.0": [.zhHans: "使用本机 AWS profile（aws configure）", .en: "使用local AWS profile（aws configure）"],
        "probe.bedrock.step.1": [.zhHans: "查询指定区域 CloudWatch 调用量", .en: "query CloudWatch metrics in regions"],
        "probe.bedrock.step.2": [.zhHans: "结合定价估算费用，可设每日预算", .en: "estimate cost with pricing; optional daily budget"],
        "probe.alibaba.step.0": [.zhHans: "区域：国内 / 国际控制台", .en: "Region: 国内 / 国际控制台"],
        "probe.alibaba.step.1": [.zhHans: "Cookie：自动从浏览器读取，或手动粘贴", .en: "Cookie: auto from browser or paste"],
        "probe.alibaba.step.2": [.zhHans: "也可使用 API Key 探测 Coding Plan 额度", .en: "or use API Key 探测 Coding Plan 额度"],
        "probe.ampcode.step.0": [.zhHans: "定位本机 amp 命令", .en: "定位local amp 命令"],
        "probe.ampcode.step.1": [.zhHans: "执行 amp usage 解析配额输出", .en: "run amp usage 解析配额输出"],
        "probe.ampcode.step.2": [.zhHans: "映射为剩余额度卡片", .en: "map to remaining quota cards"],
        "probe.kiro.step.0": [.zhHans: "定位本机 kiro-cli", .en: "定位local kiro-cli"],
        "probe.kiro.step.1": [.zhHans: "启动交互会话并发送 /usage", .en: "start interactive session, send /usage"],
        "probe.kiro.step.2": [.zhHans: "解析 credits / 周期重置信息", .en: "parse credits / 周期重置信息"],
        "probe.mistral.step.0": [.zhHans: "检查 ~/.vibe/logs/session 是否存在", .en: "check ~/.vibe/logs/session 是否存在"],
        "probe.mistral.step.1": [.zhHans: "扫描今日 session 元数据与 token", .en: "scan today's session metadata and tokens"],
        "probe.mistral.step.2": [.zhHans: "按 Devstral 定价汇总今日成本", .en: "sum today's cost with Devstral pricing"],
        "probe.opencode-go.step.0": [.zhHans: "定位本机 opencode 命令", .en: "定位local opencode 命令"],
        "probe.opencode-go.step.1": [.zhHans: "查询本地 DB 中消息与用量窗口", .en: "query local DB message/usage windows"],
        "probe.opencode-go.step.2": [.zhHans: "映射 $12/5h、$30/周、$60/月 类限额", .en: "map $12/5h、$30/周、$60/月 类限额"],
        "probe.omp.step.0": [.zhHans: "定位本机 omp 命令", .en: "定位local omp 命令"],
        "probe.omp.step.1": [.zhHans: "执行 omp usage --json", .en: "run omp usage --json"],
        "probe.omp.step.2": [.zhHans: "把每个源平台 provider 的 5h/周 等窗口显示为额度", .en: "show each source-provider 5h/week window as quotas"],
        "config.subtitle.data_source": [.zhHans: "数据获取方式", .en: "Data source", .ja: "データ取得", .ko: "데이터 소스", .ru: "Источник данных", .ar: "مصدر البيانات", .fr: "Source des données", .de: "Datenquelle", .es: "Fuente de datos", .pt: "Fonte de dados"],
        "config.subtitle.coding_plan": [.zhHans: "Coding Plan 额度跟踪", .en: "Coding Plan tracking", .ja: "Coding Plan 追跡", .ko: "Coding Plan 추적", .ru: "Coding Plan", .ar: "تتبع Coding Plan", .fr: "Suivi Coding Plan", .de: "Coding-Plan-Tracking", .es: "Seguimiento Coding Plan", .pt: "Acompanhamento Coding Plan"],
        "config.subtitle.xai": [.zhHans: "xAI 额度与凭证", .en: "xAI quota & credentials", .ja: "xAI 枠と認証", .ko: "xAI 한도 및 자격", .ru: "xAI квота и доступ", .ar: "حصة xAI وبيانات الاعتماد", .fr: "Quota et identifiants xAI", .de: "xAI-Kontingent & Anmeldedaten", .es: "Cuota y credenciales xAI", .pt: "Cota e credenciais xAI"],
        "config.subtitle.credits": [.zhHans: "AI 额度用量跟踪", .en: "AI credits usage tracking", .ja: "AI クレジット追跡", .ko: "AI 크레딧 사용 추적", .ru: "Учёт AI-кредитов", .ar: "تتبع أرصدة الذكاء", .fr: "Suivi des crédits IA", .de: "KI-Credits-Tracking", .es: "Seguimiento de créditos IA", .pt: "Acompanhamento de créditos de IA"],
        "config.subtitle.auth_fallback": [.zhHans: "认证回退设置", .en: "Authentication fallback settings", .ja: "認証フォールバック", .ko: "인증 대체 설정", .ru: "Резервная аутентификация", .ar: "إعدادات مصادقة بديلة", .fr: "Authentification de secours", .de: "Auth-Fallback", .es: "Autenticación de respaldo", .pt: "Autenticação alternativa"],
        "config.subtitle.cloudwatch": [.zhHans: "CloudWatch 用量跟踪", .en: "CloudWatch usage tracking", .ja: "CloudWatch 使用量", .ko: "CloudWatch 사용량", .ru: "CloudWatch", .ar: "تتبع CloudWatch", .fr: "Suivi CloudWatch", .de: "CloudWatch-Nutzung", .es: "Seguimiento CloudWatch", .pt: "Uso CloudWatch"],
        "config.cli_mode": [.zhHans: "CLI 模式", .en: "CLI mode", .ja: "CLI モード", .ko: "CLI 모드", .ru: "Режим CLI", .ar: "وضع CLI", .fr: "Mode CLI", .de: "CLI-Modus", .es: "Modo CLI", .pt: "Modo CLI"],
        "config.api_mode": [.zhHans: "API 模式", .en: "API mode", .ja: "API モード", .ko: "API 모드", .ru: "Режим API", .ar: "وضع API", .fr: "Mode API", .de: "API-Modus", .es: "Modo API", .pt: "Modo API"],
        "config.rpc_mode": [.zhHans: "RPC 模式", .en: "RPC mode", .ja: "RPC モード", .ko: "RPC 모드", .ru: "Режим RPC", .ar: "وضع RPC", .fr: "Mode RPC", .de: "RPC-Modus", .es: "Modo RPC", .pt: "Modo RPC"],
        "config.billing_mode": [.zhHans: "账单模式", .en: "Billing mode", .ja: "請求モード", .ko: "결제 모드", .ru: "Биллинг", .ar: "وضع الفوترة", .fr: "Mode facturation", .de: "Abrechnungsmodus", .es: "Modo facturación", .pt: "Modo faturamento"],
        "config.internal_mode": [.zhHans: "内部 API 模式", .en: "Internal API mode", .ja: "内部 API", .ko: "내부 API", .ru: "Internal API", .ar: "واجهة داخلية", .fr: "API interne", .de: "Interne API", .es: "API interna", .pt: "API interna"],
        "config.cli_desc.claude": [.zhHans: "运行 `claude /usage`。适用于任意登录方式。", .en: "Runs `claude /usage`. Works with any auth method.", .ja: "`claude /usage` を実行。任意の認証で動作。", .ko: "`claude /usage` 실행. 모든 인증 방식 지원.", .ru: "Запускает `claude /usage`.", .ar: "يشغّل `claude /usage`.", .fr: "Exécute `claude /usage`.", .de: "Führt `claude /usage` aus.", .es: "Ejecuta `claude /usage`.", .pt: "Executa `claude /usage`."],
        "config.api_desc.claude": [.zhHans: "直接调用 Anthropic API，更快，使用 OAuth 凭证。", .en: "Calls Anthropic API directly. Faster, uses OAuth credentials.", .ja: "Anthropic API を直接呼び出し。OAuth 使用。", .ko: "Anthropic API 직접 호출. OAuth 사용.", .ru: "Прямой вызов Anthropic API (OAuth).", .ar: "يستدعي Anthropic API مباشرة (OAuth).", .fr: "Appelle l’API Anthropic (OAuth).", .de: "Direkter Anthropic-API-Aufruf (OAuth).", .es: "Llama a la API de Anthropic (OAuth).", .pt: "Chama a API Anthropic (OAuth)."],
        "config.claude.cache_note": [.zhHans: "API 模式用量缓存约 15 分钟，后台刷新最快 15 分钟一次。", .en: "Usage is cached ~15 min under API rate limits; background refresh capped at 15 min.", .ja: "API モードは約15分キャッシュ。", .ko: "API 모드는 약 15분 캐시.", .ru: "Кэш ~15 мин в API-режиме.", .ar: "التخزين المؤقت نحو 15 دقيقة.", .fr: "Cache ~15 min en mode API.", .de: "Cache ~15 Min im API-Modus.", .es: "Caché ~15 min en modo API.", .pt: "Cache ~15 min no modo API."],
        "config.claude.auth_hint": [.zhHans: "在终端运行 `claude` 登录后，凭证即可使用。", .en: "Run `claude` in terminal to authenticate, then credentials will be available.", .ja: "ターミナルで `claude` ログイン後に利用可能。", .ko: "터미널에서 `claude` 로그인 후 사용 가능.", .ru: "Войдите через `claude` в терминале.", .ar: "سجّل الدخول عبر `claude` في الطرفية.", .fr: "Connectez-vous avec `claude` dans le terminal.", .de: "Mit `claude` im Terminal anmelden.", .es: "Autentícate con `claude` en la terminal.", .pt: "Autentique com `claude` no terminal."],
        "config.claude.cli_fallback": [.zhHans: "CLI 回退", .en: "CLI fallback", .ja: "CLI フォールバック", .ko: "CLI 대체", .ru: "CLI fallback", .ar: "احتياطي CLI", .fr: "Secours CLI", .de: "CLI-Fallback", .es: "Respaldo CLI", .pt: "Fallback CLI"],
        "config.claude.cli_fallback_desc": [.zhHans: "OAuth API 不可用时回退到 `claude /usage`。", .en: "Fall back to `claude /usage` if OAuth API is unavailable.", .ja: "OAuth API 不可時に CLI へ。", .ko: "OAuth API 불가 시 CLI로 전환.", .ru: "При недоступности OAuth — CLI.", .ar: "العودة إلى CLI إن تعذّر OAuth.", .fr: "Repasse en CLI si OAuth indisponible.", .de: "Fallback auf CLI ohne OAuth.", .es: "Usa CLI si falla OAuth.", .pt: "Usa CLI se OAuth falhar."],
        "config.claude.budget": [.zhHans: "Claude API 预算", .en: "Claude API Budget", .ja: "Claude API 予算", .ko: "Claude API 예산", .ru: "Бюджет Claude API", .ar: "ميزانية Claude API", .fr: "Budget API Claude", .de: "Claude-API-Budget", .es: "Presupuesto API Claude", .pt: "Orçamento API Claude"],
        "config.claude.budget_sub": [.zhHans: "费用阈值提醒", .en: "Cost threshold warnings", .ja: "費用しきい値警告", .ko: "비용 임계 경고", .ru: "Предупреждения о лимите", .ar: "تحذيرات حد التكلفة", .fr: "Alertes de seuil", .de: "Kostenschwellen", .es: "Avisos de umbral", .pt: "Avisos de limite"],
        "config.claude.budget_label": [.zhHans: "月预算（美元）", .en: "MONTHLY BUDGET (USD)", .ja: "月次予算 (USD)", .ko: "월 예산 (USD)", .ru: "Месячный бюджет (USD)", .ar: "الميزانية الشهرية (USD)", .fr: "Budget mensuel (USD)", .de: "Monatsbudget (USD)", .es: "Presupuesto mensual (USD)", .pt: "Orçamento mensal (USD)"],
        "config.claude.budget_help": [.zhHans: "接近预算阈值时发出提醒。仅适用于 Claude API 账号，不适用于 Max。", .en: "Get warnings when approaching your budget. Only Claude API accounts, not Max.", .ja: "予算接近時に警告。API のみ（Max 除く）。", .ko: "예산 근접 시 경고. API 계정만.", .ru: "Предупреждение у порога. Только API, не Max.", .ar: "تنبيه عند الاقتراب من الميزانية. API فقط.", .fr: "Alerte près du budget. Comptes API uniquement.", .de: "Warnung nahe Budget. Nur API, nicht Max.", .es: "Aviso al acercarte al presupuesto. Solo API.", .pt: "Aviso perto do orçamento. Só API."],
        "config.bedrock.title": [.zhHans: "AWS Bedrock 配置", .en: "AWS Bedrock configuration", .ja: "AWS Bedrock 設定", .ko: "AWS Bedrock 설정", .ru: "AWS Bedrock", .ar: "إعداد AWS Bedrock", .fr: "Config AWS Bedrock", .de: "AWS-Bedrock-Konfig.", .es: "Config AWS Bedrock", .pt: "Config AWS Bedrock"],
        "config.bedrock.profile": [.zhHans: "AWS 配置文件名", .en: "AWS PROFILE NAME", .ja: "AWS プロファイル", .ko: "AWS 프로필", .ru: "AWS profile", .ar: "ملف AWS", .fr: "Profil AWS", .de: "AWS-Profil", .es: "Perfil AWS", .pt: "Perfil AWS"],
        "config.bedrock.regions": [.zhHans: "区域（逗号分隔）", .en: "REGIONS (COMMA-SEPARATED)", .ja: "リージョン（カンマ区切り）", .ko: "리전(쉼표 구분)", .ru: "Регионы (через запятую)", .ar: "المناطق (مفصولة بفواصل)", .fr: "Régions (virgules)", .de: "Regionen (Komma)", .es: "Regiones (comas)", .pt: "Regiões (vírgulas)"],
        "config.bedrock.budget": [.zhHans: "每日预算（美元，可选）", .en: "DAILY BUDGET (USD, OPTIONAL)", .ja: "日次予算 (USD・任意)", .ko: "일일 예산 (USD, 선택)", .ru: "Дневной бюджет (USD)", .ar: "ميزانية يومية (USD)", .fr: "Budget quotidien (USD)", .de: "Tagesbudget (USD)", .es: "Presupuesto diario (USD)", .pt: "Orçamento diário (USD)"],
        "config.bedrock.cred_help": [.zhHans: "从已配置的 AWS profile 加载凭证。", .en: "AWS credentials are loaded from your configured profile.", .ja: "設定済みプロファイルから認証情報を読込。", .ko: "구성한 프로필에서 자격 증명 로드.", .ru: "Учётные данные из AWS profile.", .ar: "تُحمَّل بيانات الاعتماد من ملف AWS.", .fr: "Identifiants depuis le profil AWS.", .de: "Anmeldedaten aus dem AWS-Profil.", .es: "Credenciales del perfil AWS.", .pt: "Credenciais do perfil AWS."],
        "config.bedrock.configure_help": [.zhHans: "配置命令：aws configure --profile <name>", .en: "Configure with: aws configure --profile <name>", .ja: "設定: aws configure --profile <name>", .ko: "설정: aws configure --profile <name>", .ru: "aws configure --profile <name>", .ar: "aws configure --profile <name>", .fr: "aws configure --profile <name>", .de: "aws configure --profile <name>", .es: "aws configure --profile <name>", .pt: "aws configure --profile <name>"],
        "config.bedrock.open_console": [.zhHans: "打开 Bedrock 控制台", .en: "Open Bedrock Console", .ja: "Bedrock コンソール", .ko: "Bedrock 콘솔", .ru: "Консоль Bedrock", .ar: "وحدة تحكم Bedrock", .fr: "Console Bedrock", .de: "Bedrock-Konsole", .es: "Consola Bedrock", .pt: "Console Bedrock"],
        "config.zai.title": [.zhHans: "Z.ai / GLM 配置", .en: "Z.ai / GLM configuration", .ja: "Z.ai / GLM 設定", .ko: "Z.ai / GLM 설정", .ru: "Z.ai / GLM", .ar: "إعداد Z.ai / GLM", .fr: "Config Z.ai / GLM", .de: "Z.ai/GLM-Konfig.", .es: "Config Z.ai / GLM", .pt: "Config Z.ai / GLM"],
        "config.zai.lookup": [.zhHans: "Token 查找顺序", .en: "TOKEN LOOKUP ORDER", .ja: "トークン検索順", .ko: "토큰 조회 순서", .ru: "Порядок поиска токена", .ar: "ترتيب البحث عن الرمز", .fr: "Ordre de recherche du jeton", .de: "Token-Suchreihenfolge", .es: "Orden de búsqueda del token", .pt: "Ordem de busca do token"],
        "config.zai.path": [.zhHans: "settings.json 路径", .en: "SETTINGS.JSON PATH", .ja: "settings.json パス", .ko: "settings.json 경로", .ru: "Путь settings.json", .ar: "مسار settings.json", .fr: "Chemin settings.json", .de: "settings.json-Pfad", .es: "Ruta settings.json", .pt: "Caminho settings.json"],
        "config.zai.env": [.zhHans: "认证环境变量（回退）", .en: "AUTH TOKEN ENV VAR (FALLBACK)", .ja: "認証 ENV（フォールバック）", .ko: "인증 ENV (대체)", .ru: "ENV токена (fallback)", .ar: "متغير بيئة المصادقة", .fr: "Variable d’env. (secours)", .de: "Auth-ENV (Fallback)", .es: "Variable de entorno (respaldo)", .pt: "Variável de ambiente (fallback)"],
        "config.zai.empty_hint": [.zhHans: "两者留空则使用默认路径且无环境变量回退。", .en: "Leave both empty to use default path with no env var fallback.", .ja: "両方空なら既定パス、ENV なし。", .ko: "둘 다 비우면 기본 경로, ENV 없음.", .ru: "Пусто = путь по умолчанию без ENV.", .ar: "اتركهما فارغين للمسار الافتراضي.", .fr: "Vides = chemin par défaut sans ENV.", .de: "Leer = Standardpfad ohne ENV.", .es: "Vacío = ruta por defecto sin ENV.", .pt: "Vazio = caminho padrão sem ENV."],
        "config.zai.lookup1": [.zhHans: "1. 先在 settings.json 中查找 token", .en: "1. First looks for token in the settings.json file", .ja: "1. まず settings.json の token", .ko: "1. settings.json에서 토큰 검색", .ru: "1. Сначала settings.json", .ar: "1. أولاً في settings.json", .fr: "1. D’abord settings.json", .de: "1. Zuerst settings.json", .es: "1. Primero settings.json", .pt: "1. Primeiro settings.json"],
        "config.zai.lookup2": [.zhHans: "2. 文件中没有则回退到环境变量", .en: "2. Falls back to environment variable if not found in file", .ja: "2. なければ環境変数", .ko: "2. 없으면 환경 변수", .ru: "2. Иначе переменная окружения", .ar: "2. وإلا متغير البيئة", .fr: "2. Sinon variable d’environnement", .de: "2. Sonst Umgebungsvariable", .es: "2. Si no, variable de entorno", .pt: "2. Senão variável de ambiente"],
        "config.extension_settings": [.zhHans: "扩展设置", .en: "Extension settings", .ja: "拡張設定", .ko: "확장 설정", .ru: "Настройки расширения", .ar: "إعدادات الامتداد", .fr: "Réglages d’extension", .de: "Erweiterungseinstellungen", .es: "Ajustes de extensión", .pt: "Ajustes de extensão"],
        "config.clear": [.zhHans: "清除", .en: "Clear", .ja: "クリア", .ko: "지우기", .ru: "Очистить", .ar: "مسح", .fr: "Effacer", .de: "Löschen", .es: "Borrar", .pt: "Limpar"],
        "config.save_test": [.zhHans: "保存并测试连接", .en: "Save and test connection", .ja: "保存して接続テスト", .ko: "저장 후 연결 테스트", .ru: "Сохранить и проверить", .ar: "حفظ واختبار الاتصال", .fr: "Enregistrer et tester", .de: "Speichern und testen", .es: "Guardar y probar", .pt: "Salvar e testar"],
        "config.testing": [.zhHans: "正在测试连接…", .en: "Testing connection…", .ja: "接続テスト中…", .ko: "연결 테스트 중…", .ru: "Проверка…", .ar: "جارٍ اختبار الاتصال…", .fr: "Test de connexion…", .de: "Verbindung wird geprüft…", .es: "Probando conexión…", .pt: "Testando conexão…"],
        "config.env_alt": [.zhHans: "环境变量（备选）", .en: "Environment variable (fallback)", .ja: "環境変数（代替）", .ko: "환경 변수(대체)", .ru: "Переменная окружения", .ar: "متغير بيئة (بديل)", .fr: "Variable d’environnement", .de: "Umgebungsvariable", .es: "Variable de entorno", .pt: "Variável de ambiente"],
        "config.key_order": [.zhHans: "密钥查找顺序", .en: "Key lookup order", .ja: "キー検索順", .ko: "키 조회 순서", .ru: "Порядок ключей", .ar: "ترتيب البحث عن المفتاح", .fr: "Ordre des clés", .de: "Schlüsselsuche", .es: "Orden de claves", .pt: "Ordem das chaves"],
        "config.remove_key": [.zhHans: "移除 API 密钥", .en: "Remove API key", .ja: "API キーを削除", .ko: "API 키 제거", .ru: "Удалить API-ключ", .ar: "إزالة مفتاح API", .fr: "Supprimer la clé API", .de: "API-Schlüssel entfernen", .es: "Quitar clave API", .pt: "Remover chave API"],
        "config.creds_found": [.zhHans: "已找到 OAuth 凭证", .en: "OAuth credentials found", .ja: "OAuth 認証情報あり", .ko: "OAuth 자격 증명 있음", .ru: "OAuth найден", .ar: "وُجدت بيانات OAuth", .fr: "Identifiants OAuth trouvés", .de: "OAuth-Anmeldedaten gefunden", .es: "Credenciales OAuth halladas", .pt: "Credenciais OAuth encontradas"],
        "config.creds_missing": [.zhHans: "未找到 OAuth 凭证", .en: "No OAuth credentials found", .ja: "OAuth なし", .ko: "OAuth 없음", .ru: "OAuth не найден", .ar: "لا بيانات OAuth", .fr: "Pas d’identifiants OAuth", .de: "Keine OAuth-Daten", .es: "Sin credenciales OAuth", .pt: "Sem credenciais OAuth"],

        "config.alibaba.title": [.zhHans: "阿里云配置", .en: "Alibaba configuration", .ja: "Alibaba 設定", .ko: "Alibaba 설정", .ru: "Alibaba", .ar: "إعداد Alibaba", .fr: "Config Alibaba", .de: "Alibaba-Konfig.", .es: "Config Alibaba", .pt: "Config Alibaba"],
        "config.alibaba.sub": [.zhHans: "Coding Plan 额度跟踪", .en: "Coding Plan quota tracking", .ja: "Coding Plan 枠", .ko: "Coding Plan 한도", .ru: "Coding Plan", .ar: "تتبع Coding Plan", .fr: "Suivi Coding Plan", .de: "Coding-Plan-Kontingent", .es: "Cuota Coding Plan", .pt: "Cota Coding Plan"],
        "config.alibaba.cookie_source": [.zhHans: "Cookie 来源", .en: "COOKIE SOURCE", .ja: "Cookie ソース", .ko: "쿠키 소스", .ru: "Источник cookie", .ar: "مصدر الكوكي", .fr: "Source du cookie", .de: "Cookie-Quelle", .es: "Origen de cookie", .pt: "Origem do cookie"],
        "config.alibaba.cookie": [.zhHans: "Cookie 字符串", .en: "COOKIE STRING", .ja: "Cookie 文字列", .ko: "쿠키 문자열", .ru: "Строка cookie", .ar: "سلسلة الكوكي", .fr: "Chaîne cookie", .de: "Cookie-String", .es: "Cadena cookie", .pt: "String de cookie"],
        "config.alibaba.cookie_prompt": [.zhHans: "粘贴 Cookie…", .en: "Paste cookie string…", .ja: "Cookie を貼付…", .ko: "쿠키 붙여넣기…", .ru: "Вставьте cookie…", .ar: "الصق الكوكي…", .fr: "Coller le cookie…", .de: "Cookie einfügen…", .es: "Pegar cookie…", .pt: "Colar cookie…"],
        "config.alibaba.open": [.zhHans: "打开阿里云控制台", .en: "Open Alibaba Cloud Console", .ja: "Alibaba コンソール", .ko: "Alibaba 콘솔", .ru: "Консоль Alibaba", .ar: "وحدة تحكم Alibaba", .fr: "Console Alibaba", .de: "Alibaba-Konsole", .es: "Consola Alibaba", .pt: "Console Alibaba"],
        "config.copilot.billing_desc": [.zhHans: "使用 GitHub Billing API。需要带 Plan:read 的细粒度 PAT。", .en: "Uses GitHub Billing API. Requires fine-grained PAT with 'Plan: read'.", .ja: "GitHub Billing API。Plan:read の PAT が必要。", .ko: "GitHub Billing API. Plan:read PAT 필요.", .ru: "GitHub Billing API. Нужен PAT с Plan:read.", .ar: "GitHub Billing API. يتطلب PAT بصلاحية Plan:read.", .fr: "API Billing GitHub. PAT fine-grained Plan:read requis.", .de: "GitHub Billing API. PAT mit Plan:read nötig.", .es: "API Billing de GitHub. PAT con Plan:read.", .pt: "API Billing do GitHub. PAT com Plan:read."],
        "config.copilot.username": [.zhHans: "GitHub 用户名", .en: "GITHUB USERNAME", .ja: "GitHub ユーザー名", .ko: "GitHub 사용자명", .ru: "Имя GitHub", .ar: "اسم مستخدم GitHub", .fr: "Nom d’utilisateur GitHub", .de: "GitHub-Benutzername", .es: "Usuario de GitHub", .pt: "Usuário GitHub"],
        "config.copilot.token": [.zhHans: "个人访问令牌", .en: "PERSONAL ACCESS TOKEN", .ja: "パーソナルアクセストークン", .ko: "개인 액세스 토큰", .ru: "Personal Access Token", .ar: "رمز الوصول الشخصي", .fr: "Jeton d’accès personnel", .de: "Personal Access Token", .es: "Token de acceso personal", .pt: "Token de acesso pessoal"],
        "config.copilot.token_saved": [.zhHans: "令牌已保存", .en: "Token saved!", .ja: "トークン保存済み", .ko: "토큰 저장됨", .ru: "Токен сохранён", .ar: "تم حفظ الرمز", .fr: "Jeton enregistré", .de: "Token gespeichert", .es: "Token guardado", .pt: "Token salvo"],
        "config.copilot.env": [.zhHans: "认证环境变量（备选）", .en: "AUTH TOKEN ENV VAR (ALTERNATIVE)", .ja: "認証 ENV（代替）", .ko: "인증 ENV (대체)", .ru: "ENV токена", .ar: "متغير بيئة المصادقة", .fr: "Variable d’env. (alt.)", .de: "Auth-ENV (Alternative)", .es: "Variable de entorno (alt.)", .pt: "Variável de ambiente (alt.)"],
        "config.copilot.monthly": [.zhHans: "每月 AI 额度上限", .en: "MONTHLY AI CREDITS LIMIT", .ja: "月次 AI クレジット上限", .ko: "월 AI 크레딧 한도", .ru: "Месячный лимит AI", .ar: "حد أرصدة AI الشهري", .fr: "Limite mensuelle de crédits IA", .de: "Monatliches KI-Credits-Limit", .es: "Límite mensual de créditos IA", .pt: "Limite mensal de créditos de IA"],

    ]
}

extension String {
    /// Localize UI key on the main actor.
    @MainActor
    var l10n: String { L10n.shared.t(self) }
}

