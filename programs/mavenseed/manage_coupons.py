#!/usr/bin/env python3
"""Create, update, and delete coupons on the Mavenseed course creation
platform."""
import os
from dataclasses import dataclass
from enum import Enum
from typing import Sequence

import dotenv
import pyperclip
import requests
from datargs import arg, parse

dotenv.load_dotenv()

YOUR_MAVENSEED_URL: str = os.environ.get("MAVENSEED_URL", "")
YOUR_EMAIL: str = os.environ.get("MAVENSEED_EMAIL", "")
YOUR_PASSWORD: str = os.environ.get("MAVENSEED_PASSWORD", "")

API_SLUG_LOGIN: str = "/api/login"
API_SLUG_COUPONS: str = "/api/v1/coupons"


class EligibleType(Enum):
    """Enum representing types of purchases that are eligible for a given
    coupon."""

    orders = "orders"
    subscriptions = "subscriptions"


class CouponType(Enum):
    """Enum representing the type of coupon to create."""

    coupon = "coupon"
    gift_card = "gift_card"


class CouponDuration(Enum):
    """Enum representing valid coupon durations."""

    once = "once"
    repeating = "repeating"
    forever = "forever"


class ResponseCodes(Enum):
    """Rest API response codes."""

    OK: int = 200
    CREATED: int = 201
    NO_CONTENT: int = 204
    BAD_REQUEST: int = 400
    UNAUTHORIZED: int = 401
    FORBIDDEN: int = 403
    NOT_FOUND: int = 404
    METHOD_NOT_ALLOWED: int = 405
    CONFLICT: int = 409
    UNPROCESSABLE_ENTITY: int = 422
    INTERNAL_SERVER_ERROR: int = 500
    NOT_IMPLEMENTED: int = 501


@dataclass
class Args:
    """Command-line arguments."""

    discount_amount: int = arg(
        positional=True,
        default=50,
        help="""Amount of discount to apply to the coupon.
        
        By default, it's in percent. If you use the option --use-amount,
        it represents an amount in cents instead.

        In that case, an amount of 100 means 100 cents.
        
        Default: 50.""",
    )
    delete: bool = arg(
        default=False,
        help="Delete an existing coupon instead of creating a new one.",
    )
    update: bool = arg(
        default=False,
        help="Update an existing coupon instead of creating a new one.",
    )
    use_amount: bool = arg(
        default=False,
        help="If True, the discount amount is in centers instead of percent.",
        aliases=["-a"],
    )
    max_uses: int = arg(
        default=1,
        help="Number of times a coupon can be used. Default: 1.",
        aliases=["-m"],
    )
    supported_types: Sequence[EligibleType] = arg(
        default=tuple([EligibleType.orders]),
        help=f"Type of purchases the coupon supports. Possible values:{[t.value for t in EligibleType]}.",
    )
    coupon_code: str = arg(
        default="",
        help="The coupon code to create. "
        "If empty, a coupon code will be generated automatically.",
        aliases=["-c"],
    )
    mavenseed_url: str = arg(
        default=YOUR_MAVENSEED_URL,
        help="""the url of your mavenseed website.

        If you omit this option, the program tries to read it from the
        environment variable MAVENSEED_URL.
        """,
        aliases=["-u"],
    )
    email: str = arg(
        default=YOUR_EMAIL,
        help="""Your email to log into your Mavenseed's admin account.

        If you omit this option, the program tries to read it from the
        environment variable MAVENSEED_EMAIL.
        """,
        aliases=["-e"],
    )
    password: str = arg(
        default=YOUR_PASSWORD,
        help="""Your password to log into your Mavenseed's admin account.

        If you omit this option, the program tries to read it from the
        environment variable MAVENSEED_PASSWORD.
        """,
        aliases=["-p"],
    )


def get_auth_token(api_url: str, email: str, password: str) -> str:
    """Logs into the Mavenseed API using your email and password.

    Returns an auth token for future API calls."""
    response = requests.post(
        api_url + API_SLUG_LOGIN, data={"email": email, "password": password}
    )
    auth_token = response.json()["auth_token"]
    return auth_token


def create_coupon(auth_token: str, mavenseed_url: str, args: Args) -> None:
    """Creates a coupon with the given coupon code on the Mavenseed platform."""

    def generate_random_coupon_code() -> str:
        """Generates a random coupon code with 8 characters."""
        import random
        import string

        return "".join(random.choices(string.ascii_uppercase + string.digits, k=8))

    payload: dict = {
        "internal_coupon_id": args.coupon_code
        if args.coupon_code
        else generate_random_coupon_code(),
        "currency": "USD",
        "eligible_types": [t.value for t in args.supported_types],
        "duration": CouponDuration.once.value,
        "coupon_type": CouponType.coupon.value,
    }
    discount_key = "amount_off" if args.use_amount else "percent_off"
    payload[discount_key] = args.discount_amount
    if args.max_uses:
        payload["max_redemptions"] = args.max_uses

    response = requests.post(
        mavenseed_url + API_SLUG_COUPONS,
        headers={"Authorization": f"Bearer {auth_token}"},
        json=payload,
    )
    output: dict = response.json()
    coupon = output['internal_coupon_id']
    if response.status_code != ResponseCodes.CREATED.value:
        raise RuntimeError(
            f"Couldn't create coupon with code {coupon}. "
            f"Response code: {response.status_code}."
        )
    else:
        pyperclip.copy(coupon)
        print(
            f"Coupon {coupon} was created successfully and copied to your clipboard."
        )


def main():
    def validate_args(args: Args) -> None:
        """Checks the given command-line arguments and raises an error if some
        values are invalid."""
        if args.delete and args.update:
            raise ValueError("You can't use --delete and --update at the same time.")

        if not args.mavenseed_url:
            raise ValueError(
                """You must provide a Mavenseed URL via the --mavenseed-url command line
                option or set the MAVENSEED_URL environment variable."""
            )
        if args.discount_amount <= 0:
            raise ValueError("You must provide a positive amount of discount.")
        if args.max_uses < 1:
            raise ValueError("You must provide a positive number of max uses.")

        if not set(args.supported_types).issubset(set(EligibleType)):
            raise ValueError(
                f"You must provide a valid set of eligible types. Possible values: {[t.value for t in EligibleType]}"
            )

    args: Args = parse(Args)
    validate_args(args)
    auth_token: str = get_auth_token(args.mavenseed_url, args.email, args.password)

    if args.delete:
        raise NotImplementedError("Delete is not implemented yet.")
    elif args.update:
        raise NotImplementedError("Update is not implemented yet.")
    else:
        create_coupon(auth_token, args.mavenseed_url, args)


if __name__ == "__main__":
    main()
