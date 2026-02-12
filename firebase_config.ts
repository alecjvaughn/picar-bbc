// Import the functions you need from the SDKs you need
import { initializeApp } from "firebase/app";
import { getAnalytics } from "firebase/analytics";
// TODO: Add SDKs for Firebase products that you want to use
// https://firebase.google.com/docs/web/setup#available-libraries

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: "aleclabs-website.firebaseapp.com",
  projectId: "aleclabs-website",
  storageBucket: "aleclabs-website.firebasestorage.app",
  messagingSenderId: "670714987285",
  appId: "1:670714987285:web:083cedf0b3c9354edddf1c",
  measurementId: "G-HV4KDBW3V5"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const analytics = getAnalytics(app);