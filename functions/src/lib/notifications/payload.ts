import type { MulticastMessage } from "firebase-admin/messaging";

import { FCM_MESSAGE_TTL_MS, PAYLOAD_VERSION } from "./constants";
import type { NotificationType, RenderedNotification } from "./types";

/**
 * Builds the FCM message (notification + data). Pure.
 *
 * Data payload (all strings, plan §4.6): `v`, `type`, `audience`,
 * `recipientUid` (customer only), one entity id (`orderId` / `reviewId` /
 * `productId`) and `notificationId` (inbox row id). It deliberately carries
 * NO route name, URL or free text - the app maps `type` to a hard-coded
 * destination, so a tampered payload can only select a pre-approved screen.
 */

const ID_SHAPE = /^[A-Za-z0-9_.:-]{1,200}$/;

export class PushPayloadError extends Error {}

type EntityKey = "orderId" | "reviewId" | "productId";

const ENTITY_KEY_BY_TYPE: Partial<Record<NotificationType, EntityKey>> = {
  order_placed: "orderId",
  order_confirmed: "orderId",
  order_shipped: "orderId",
  order_delivered: "orderId",
  order_cancelled: "orderId",
  admin_new_order: "orderId",
  review_hidden: "reviewId",
  review_rejected: "reviewId",
  review_restored: "reviewId",
  admin_review_flagged: "reviewId",
  admin_low_stock: "productId",
  admin_out_of_stock: "productId",
};

function checkedId(value: string, name: string): string {
  if (!ID_SHAPE.test(value)) throw new PushPayloadError(`invalid ${name}`);
  return value;
}

export interface PushDataInput {
  rendered: RenderedNotification;
  /** Required for customer notifications (client re-checks it on tap). */
  recipientUid?: string;
  /** Inbox row id, when one exists. */
  notificationId?: string;
}

export function buildPushData(input: PushDataInput): Record<string, string> {
  const { rendered } = input;
  const data: Record<string, string> = {
    v: PAYLOAD_VERSION,
    type: rendered.type,
    audience: rendered.audience,
  };

  if (rendered.audience === "customer") {
    if (!input.recipientUid) throw new PushPayloadError("customer push requires recipientUid");
    data.recipientUid = checkedId(input.recipientUid, "recipientUid");
  }

  const key = ENTITY_KEY_BY_TYPE[rendered.type];
  if (key && rendered.entityId) {
    data[key] = checkedId(rendered.entityId, key);
  }
  if (input.notificationId) {
    data.notificationId = checkedId(input.notificationId, "notificationId");
  }
  return data;
}

/** Build a multicast message for a non-empty, deduplicated token batch. */
export function buildMulticastMessage(
  tokens: string[],
  rendered: RenderedNotification,
  data: Record<string, string>,
): MulticastMessage {
  return {
    tokens,
    notification: { title: rendered.title, body: rendered.body },
    data,
    android: {
      priority: rendered.androidPriority,
      ttl: FCM_MESSAGE_TTL_MS,
      notification: {
        channelId: rendered.channelId,
        tag: rendered.tag,
      },
    },
  };
}
