# AHVI

Flutter client for the AHVI demo app.

## Demo Priority

Use these paths for the May 1 demo:

- Sign in with the seeded demo Appwrite user.
- Open Style Chat and ask: "What should I wear today?"
- Ask: "Style me for dinner from my wardrobe."
- Open Fitness and ask: "Give me a 20min workout plan."

Visual wardrobe capture should only be shown when backend R2 and RunPod/R2 image services have passed a smoke test.

## Required Frontend Env

Create `.env` from `.env.example` and fill only public frontend values:

```env
EXPO_PUBLIC_APPWRITE_ENDPOINT=
EXPO_PUBLIC_APPWRITE_PROJECT_ID=
EXPO_PUBLIC_APPWRITE_DATABASE_ID=
EXPO_PUBLIC_APPWRITE_COLLECTION_OUTFITS=
EXPO_PUBLIC_APPWRITE_COLLECTION_USERS=
EXPO_PUBLIC_APPWRITE_COLLECTION_SAVED_BOARDS=
EXPO_PUBLIC_APPWRITE_COLLECTION_SKINCARE=
EXPO_PUBLIC_APPWRITE_COLLECTION_WORKOUT_OUTFITS=
EXPO_PUBLIC_APPWRITE_COLLECTION_BILLS=
EXPO_PUBLIC_APPWRITE_COLLECTION_COUPONS=
EXPO_PUBLIC_APPWRITE_COLLECTION_MEDS=
EXPO_PUBLIC_APPWRITE_COLLECTION_MED_LOGS=
EXPO_PUBLIC_APPWRITE_COLLECTION_MEAL_PLANS=
EXPO_PUBLIC_APPWRITE_COLLECTION_LIFE_GOALS=
PLANS_COLLECTION_ID=
EXPO_PUBLIC_BACKEND_API_URL=http://localhost:8000
```

Do not put backend secrets, R2 secrets, Anthropic keys, or RunPod keys in Flutter env.

## Location Context

`LocationContextService` stores the canonical location context in
`SharedPreferences`, scoped by the authenticated Appwrite user ID. The deployed
users collection only supports identity, onboarding, style preference, and shop
preference fields; none is a safe location/context field. The client therefore
does not claim Appwrite profile persistence and does not overload an unrelated
field. Backend requests receive the local canonical context through their
existing `user_profile` and/or `context` payloads. The centralized location
service does not contact a weather provider; backend-bound flows resolve
weather server-side.

## Run

```bash
flutter pub get
flutter analyze
flutter run
```

Backend must be running separately with Appwrite auth configured, or local emergency `AUTH_REQUIRED=false` for isolated demo testing.
