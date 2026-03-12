const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();

// Generate rent dues on 1st of each month
exports.generateRentDues = functions.pubsub
    .schedule("0 0 1 * *")
    .timeZone("Africa/Addis_Ababa")
    .onRun(async (context) => {
      const tenantsSnapshot = await db.collection("tenants").get();
      const batch = db.batch();
      const now = admin.firestore.Timestamp.now();
      const dueMonth = `${now.toDate().getFullYear()}-${String(
          now.toDate().getMonth() + 1,
      ).padStart(2, "0")}`;

      tenantsSnapshot.docs.forEach((doc) => {
        const tenant = doc.data();
        const dueRef = db.collection("rent_due").doc();
        batch.set(dueRef, {
          tenantId: doc.id,
          tenantName: tenant.name,
          propertyId: tenant.propertyId,
          amount: tenant.monthlyRent,
          dueMonth: dueMonth,
          dueDate: admin.firestore.Timestamp.fromDate(
              new Date(now.toDate().getFullYear(), now.toDate().getMonth(), 5),
          ),
          status: "pending",
          createdAt: now,
        });
      });

      await batch.commit();
      functions.logger.info(
          `Generated rent dues for ${tenantsSnapshot.size} tenants
           for month ${dueMonth}`,
      );
      return null;
    });

// Low‑stock check and notifications
exports.checkLowStock = functions.pubsub
    .schedule("0 8 * * *")
    .timeZone("Africa/Addis_Ababa")
    .onRun(async (context) => {
      const productsSnapshot = await db.collection("products").get();
      const materialsSnapshot = await db.collection("materials").get();
      const lowStockItems = [];

      productsSnapshot.docs.forEach((doc) => {
        const data = doc.data();
        if ((data.stock || 0) < (data.minimumLevel || 5)) {
          lowStockItems.push(`Product: ${data.name} (stock: ${data.stock})`);
        }
      });

      materialsSnapshot.docs.forEach((doc) => {
        const data = doc.data();
        if ((data.stock || 0) < (data.minimumLevel || 5)) {
          lowStockItems.push(`Material: ${data.name} (stock: ${data.stock})`);
        }
      });

      if (lowStockItems.length > 0) {
        const message = {
          notification: {
            title: "Low Stock Alert",
            body:
            lowStockItems.slice(0, 3).join("\n") +
            (lowStockItems.length > 3 ?
              `\n+${lowStockItems.length - 3} more` :
              ""),
          },
          topic: "admins",
        };
        try {
          await admin.messaging().send(message);
          functions.logger.info("Low stock notification sent");
        } catch (e) {
          functions.logger.error("FCM send failed", e);
        }
      }
      return null;
    });
