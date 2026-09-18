# 🚀 iOS CI/CD Core: Plug-and-Play Automation Platform

[![Fastlane](https://img.shields.io/badge/fastlane-2.231+-00F376.svg?style=flat&logo=fastlane)](https://fastlane.tools)
[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-Reusable_Workflows-2088FF.svg?style=flat&logo=github-actions)](https://github.com/features/actions)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20macOS-lightgrey.svg?style=flat&logo=apple)](https://developer.apple.com/ios/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0%20Ready-F05138.svg?logo=swift)](https://swift.org)
[![Architecture](https://img.shields.io/badge/Architecture-Modular%20%26%20Decoupled-blueviolet.svg)](#architecture)

> **Enterprise-Grade, Zero-Friction iOS CI/CD as a Service**  
> Tüm iOS projelerinizi (SwiftUI, UIKit, Multi-module) tek merkezden yönetin. Kod tekrarını sıfırlayın, TestFlight dağıtımlarını, otomatik Changelog üretimini ve Slack bildirimlerini **tek bir satır kodla** projelerinize dahil edin.

---

## ⚡ Geleneksel vs. Core Mimari (Before vs. After)

| Özellik | Geleneksel Yaklaşım ❌ | `ios-cicd-core` Mimarisi ✅ |
| :--- | :--- | :--- |
| **Yeni Proje Kurulumu** | 2-4 saat (Fastfile & GHA kopyala-yapıştır) | **2 Dakika** (`import_from_git` + 5 satır) |
| **Bakım Maliyeti** | 1 kural değiştiğinde 10 repo güncelleme | **Tek Noktadan** (Sadece `ios-cicd-core` güncellenir) |
| **Sürümleme & Güvenlik** | Takipsiz ve kontrolsüz scriptler | **SemVer Git Tags** (`@v1.0.0`) ile kırılma koruması |
| **Sürüm Notları (Changelog)** | Elle yazılan tutarsız notlar | **Otomatik Git Log Ayrıştırma** (TestFlight & Slack) |
| **Hata Yönetimi** | Terminal loglarında kaybolan hatalar | **Block Kit Slack Kartı** (Commit, Branch, Duration, Trace) |
| **Derleme Süresi Takibi** | Bilinmeyen gecikmeler | **Otomatik Süre Ölçümü** (`⏱️ Build Time: 1m 24s`) |

---

## 🏛️ Mimari Tasarım (Architecture)

```mermaid
flowchart TD
    subgraph Core ["ios-cicd-core (Merkezi Platform)"]
        RW["Reusable Workflows<br/>(reusable-pipeline.yml)"]
        CA["Composite Actions<br/>(setup-ios-env)"]
        FL["Universal Fastfile<br/>(lint, test, build, deploy)"]
        SA["Custom Action<br/>(send_detailed_slack + metrics)"]
        CL["Automated Changelog<br/>(Git Commits Extractor)"]
    end

    subgraph App1 ["Target App 1: Fitly (SwiftUI)"]
        W1["deploy.yml (4 satır)"]
        F1["Fastfile (5 satır)"]
    end

    subgraph App2 ["Target App 2: Goldwise (Fintech/UIKit)"]
        W2["deploy.yml (4 satır)"]
        F2["Fastfile (5 satır)"]
    end

    RW -.->|Workflow Call| W1
    RW -.->|Workflow Call| W2
    FL -->|Universal Lanes| F1
    FL -->|Universal Lanes| F2
    SA -->|Zengin Slack Kartları| F1
    SA -->|Zengin Slack Kartları| F2
    CL -->|Otomatik Sürüm Notları| F1
    CL -->|Otomatik Sürüm Notları| F2
```

---

## 💎 Öne Çıkan Yetenekler (Core Features)

### 1. 📝 Otomatik Changelog & Release Notes Üretimi
Son Git commit geçmişini otomatik olarak analiz eder, madde işaretlerine dönüştürür ve:
* TestFlight'ın *"What to Test"* açıklamasına otomatik basar.
* Slack bildirim kartına *"🚀 Release Notes"* alanı olarak ekler.

### 2. ⏱️ Performans ve Süre Ölçümü (Benchmarking)
Her pipeline adımının (`universal_lint`, `universal_test`, `universal_build`) başlangıç ve bitiş zamanını milisaniye hassasiyetinde takip eder ve Slack raporuna `⏱️ 1m 35s` şeklinde iliştirir.

### 3. 🎯 GitHub Reusable Workflow (`workflow_call`)
Hedef projelerdeki karmaşık YAML dosyalarını tarihe gömer. Tek bir çağrıyla tüm ortam kurulumunu, önbellekleri ve derleme adımlarını yürütür.

### 4. 🛡️ SwiftLint & Kod Kalitesi Geçidi (`universal_lint`)
Tüm PR'larda kod standartlarını denetler, ihlal durumunda pipeline'ı güvenle durdurur.

---

## 🔌 Tüketici Projeye Entegrasyon

### 1. `fastlane/Fastfile` (Sadece 5 Satır!)

```ruby
# encoding: utf-8
default_platform(:ios)

# Merkezi repoyu Git üzerinden dahil et
import_from_git(
  url: "https://github.com/hakankorhasan/ios-cicd-core.git",
  branch: "main" # veya production için tag: "v1.0.0"
)

platform :ios do
  desc "TestFlight Dağıtımı"
  lane :release do
    universal_testflight_deploy(
      scheme: "Fitly",
      bundle_id: "com.hakan.fitly",
      app_name: "Fitly"
    )
  end

  desc "Test Koşumu"
  lane :test do
    universal_test(scheme: "Fitly")
  end
end
```

### 2. GitHub Actions (`.github/workflows/ci.yml` - Sadece 4 Satır!)

```yaml
name: CI/CD Pipeline
on: [push]

jobs:
  build:
    uses: hakankorhasan/ios-cicd-core/.github/workflows/reusable-pipeline.yml@v1.0.0
    with:
      scheme: 'Fitly'
      lane: 'test'
    secrets:
      SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

---

## 🧪 Yerel Simülasyon ve Test

Apple Developer ücretli sertifikası gerekmeden tüm sistemi yerel ortamda test etmek için:

```bash
# 1. SwiftLint & Kod Kalite Kontrolü
fastlane universal_lint scheme:"Fitly"

# 2. Otomatik Changelog & Süre Takibi ile Mock Dağıtım
fastlane universal_mock_deploy app_name:"Fitly" scheme:"FitlyApp" bundle_id:"com.hakan.fitly"
```
