import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

import { FUNCTIONS_REGION } from "./config";
import { applyFavoriteChange, favoriteChangeKind } from "./lib/productStats";

/**
 * `adjustFavoriteCount` — Phase 9.3 "Dynamic Home Content" Stage 2.
 *
 * Maintains `productStats/{productId}.favoriteCount` from genuine
 * `users/{uid}/favorites/{productId}` create / delete events. (`favorites`
 * documents are never updated in place — the rule forbids it — so an update
 * event, if it somehow occurs, is not a count change and is ignored.)
 *
 * Exactly idempotent AND convergent: `applyFavoriteChange` ignores the event
 * payload's direction and reconciles `favoriteCount` against the live
 * `users/{uid}/favorites/{productId}` document inside a transaction, keeping a
 * per-(user,product) `productStats/{productId}/favoriteVoters/{uid}` guard doc
 * that exists iff the pair is currently counted. Duplicate, reversed,
 * out-of-order or stale-retried deliveries all converge — `favoriteCount`
 * ends equal to the number of live favourite docs, never drifting.
 */
export const adjustFavoriteCount = onDocumentWritten(
  {
    region: FUNCTIONS_REGION,
    document: "users/{uid}/favorites/{productId}",
    memory: "256MiB",
    retry: true,
  },
  async (event) => {
    // Only a create or a delete can change the count; an in-place update
    // (which the security rule forbids anyway) is skipped. The direction is
    // NOT trusted past this point — `applyFavoriteChange` reconciles against
    // the live favourite doc.
    const kind = favoriteChangeKind(
      event.data?.before?.exists ?? false,
      event.data?.after?.exists ?? false,
    );
    if (kind === null) return;

    const uid = event.params.uid as string;
    const productId = event.params.productId as string;

    try {
      const outcome = await applyFavoriteChange({ productId, uid });
      logger.info("productStats: favourite adjustment", {
        uid,
        productId,
        event: kind,
        outcome: outcome.kind,
      });
    } catch (err) {
      logger.error("productStats: favourite adjustment failed", {
        uid,
        productId,
        event: kind,
        err,
      });
      throw err; // retry — reconciliation is idempotent
    }
  },
);
